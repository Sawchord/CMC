/* "Copyright (c) 2016 
 * Leon Tan 
 * Georg-August University of Goettingen
 * All rights reserved"
 * 
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR 
 * HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 * 
 */
 
#include "CMC.h"

#include "TinyECC/NN.h"
#include "TinyECC/ECC.h"
#include "TinyECC/ECIES.h"

#include "TinyECC/sha1.h"

#include "crypto/crypto.h"

/* the client only option hints the compiler 
 * to remove all server related if expressions */
#ifdef CMC_CLIENT_ONLY
#define IS_SERVER 0
#else
#define IS_SERVER sock->sync_state != CMC_CLOSED
#endif

module CMCP {
  provides interface CMC[uint8_t client];
  provides interface Init;
  uses {
    interface Boot;
    interface Timer<TMilli>;
    
    interface Random;
    
    interface Packet;
    interface AMSend;
    interface Receive;
    
    interface BlockCipher;
    
    interface NN;
    interface ECC;
    interface ECIES;
    
    interface SHA1;
    
  }
} implementation {
  
  enum {
    N_SOCKS = uniqueCount("CMC_SOCKS"),
  };
  
  message_t pkt;
  
  /* holds all sockets to cmc servers in an array */
  cmc_sock_t socks[N_SOCKS];
  
  
  /* --------- helpful functions ---------- */
  
  
  /* sends out a sync message */
  error_t send_sync(cmc_sock_t* sock, Point* pub_key) {
    
    uint8_t packet_size;
    cmc_hdr_t* packet_hdr;
    cmc_sync_hdr_t* sync_hdr;
    
    // calculate the packet size
    packet_size = sizeof(cmc_hdr_t) + sizeof(cmc_sync_hdr_t);
    
    // set up the packet
    packet_hdr = (cmc_hdr_t*)(call Packet.getPayload(&pkt, packet_size));
    
    // calculate the sunc_header pointer by offsetting
    sync_hdr = (cmc_sync_hdr_t*) ( (void*) packet_hdr + sizeof(cmc_hdr_t));
    
    // fill the packet with stuff
    packet_hdr->src_id = sock->local_id;
    packet_hdr->dst_id = 0xff; // since the servers id is unknown of now
    packet_hdr->group_id = sock->group_id;
    
    
    // fill in the public key of the server
    call ECC.point2octet((uint8_t*) &(sync_hdr->public_key), 
      CMC_POINT_SIZE, pub_key, FALSE);
    DBG("sync send\n");
    return call AMSend.send(AM_BROADCAST_ADDR, &pkt, packet_size);
    
  }
  
  /* simple sha1 hash of a message */
  error_t sha1_hash(void* output, void* input, uint16_t input_len) {
    SHA1Context ctx;
    error_t e;
    e = call SHA1.reset(&ctx);
    e = call SHA1.update(&ctx, input, input_len);
    e = call SHA1.digest(&ctx, output);
    return e;
  }
  
  
  
  /*error_t send_data(cmc_sock_t* sock, uint16_t dst_id,
    void* data, uint16_t data_len) {*/
  error_t send_data(cmc_sock_t* sock) {
    
    cmc_hdr_t* message_hdr;
    cmc_data_hdr_t* data_header;
    
    // the messages body needs to be constructed before it can be encrypted
    // this requires two memcopys ... should be retweaked in the future
    cmc_clear_data_hdr_t clear_data;
    
    uint8_t message_size; /* size of the complete messahe including main header */
    uint8_t payload_size; /* actual size of the data field */
    uint8_t pad_bytes;
    uint16_t i;
    
    uint8_t data_len = sock->last_msg_len;
    
    DBG("data_len:%d\n", data_len);
    
    // calculate the number of padding bytes needed
    pad_bytes = (CMC_CC_BLOCKSIZE - ( (data_len + sizeof(uint16_t) + CMC_HASHSIZE)
      % CMC_CC_BLOCKSIZE) % CMC_CC_BLOCKSIZE);
    
    // check for the right conditions to send
    if ( !(sock->com_state == CMC_ESTABLISHED || sock->com_state == CMC_ACKPENDING1) ) {
      DBG("socket not in condition to send\n");
      return FAIL;
    }
    if (data_len + pad_bytes > CMC_DATAFIELD_SIZE) {
      DBG("data too long\n");
      return FAIL;
    }
    
    // calculate sized
    //              group_id          sha1 hash size  data        padding
    payload_size = sizeof(uint16_t) + CMC_HASHSIZE + data_len + pad_bytes;
    //            header               encrypted data  data length field
    message_size = sizeof(cmc_hdr_t) + payload_size + sizeof(uint16_t);
    
    
    //build the data packet
    clear_data.group_id = sock->group_id;
    memcpy(&(clear_data.data), &(sock->last_msg), data_len);
    // fill the rest with padbytes
    memset((void*) &(clear_data.data) + data_len, 0, pad_bytes);
    
    if (sha1_hash(&(clear_data.hash), &(clear_data.data), 
      data_len + pad_bytes) != SUCCESS) {
      DBG("error in send while hashing\n");
      return FAIL;
    }
    
    
    // prepare the message to send
    message_hdr = (cmc_hdr_t*)(call Packet.getPayload(&pkt, message_size));
    data_header = (cmc_data_hdr_t*)( (void*) message_hdr + sizeof(cmc_hdr_t) );
    
    //DBG("message_hdr:%p data_header:%p\n", message_hdr, data_header);
    DBG("payload_size: %d pad_bytes: %d \n", payload_size, pad_bytes);
    
    message_hdr->src_id = sock->local_id;
    message_hdr->group_id = sock->group_id;
    message_hdr->dst_id = sock->last_dst;
    message_hdr->type = CMC_DATA;
    
    data_header->length = data_len;
    
    // this is sooo ugly, needs some refactoring
    for (i = 0; i < payload_size; i += CMC_CC_BLOCKSIZE) {
      if (call BlockCipher.encrypt(&(sock->master_key), 
        ((uint8_t*) &clear_data) + i, ((uint8_t*) &(data_header->enc_data)) + i ) 
        != SUCCESS) {
        DBG("error in send while encrypting\n");
        return FAIL;
      }
    }
    
    //DBG("here come dat packet:");
    //print_hex(message_hdr, message_size);
    
    
    //DBG("send_data: %s\n", sock->last_msg);
    DBG("send_data\n");
    return call AMSend.send(AM_BROADCAST_ADDR, &pkt, message_size);
    
    // set new com_states if not multicast
    if (sock->last_dst != 0xff) {
      if (IS_SERVER) {
        sock->com_state = CMC_ACKPENDING2;
      }
      else {
        sock->com_state = CMC_ACKPENDING1;
      }
    }
    return SUCCESS;
    
  } /* send_data */
  
  
  /*error_t ack_data(uint8_t client, uint16_t dst_id,
     void* data, uint16_t data_len) {*/
    
  error_t ack_data(cmc_sock_t* sock) {
    cmc_hdr_t* ack_header;
    cmc_ack_hdr_t* ack_field;
    
    uint8_t ack_size;
    
    
    ack_size = sizeof(cmc_hdr_t) + sizeof(cmc_ack_hdr_t);
    ack_header = (cmc_hdr_t*)(call Packet.getPayload(&pkt, ack_size));
    ack_field = (cmc_ack_hdr_t*)( (void*) ack_header + sizeof(cmc_hdr_t));
    
    ack_header->src_id = sock->local_id;
    ack_header->group_id = sock->group_id;
    ack_header->dst_id = sock->last_dst;
    ack_header->type = CMC_ACK;
    
    if (sha1_hash(ack_field, &(sock->last_msg), sock->last_msg_len) != SUCCESS) {
      DBG("hashing error in ack\n");
      return FAIL;
    }
    
    // FIXME: this packet seems faulty
    if (call AMSend.send(AM_BROADCAST_ADDR, &pkt, ack_size) != SUCCESS) {
      DBG("error while sending ack");
      return FAIL;
    }
    
    return SUCCESS;
  }
  
  /* --------- implemented events --------- */
  /* startup initialization */
  command error_t Init.init() {
    uint8_t i;
    
    call ECC.init();
    
    for (i = 0; i < N_SOCKS; i++) {
      
      // set all sockets to closed
      socks[i].sync_state = CMC_CLOSED;
      socks[i].com_state = CMC_CLOSED;
      socks[i].retry_counter = 0;
      socks[i].retry_timer = 0;
    }
    
    return SUCCESS;
  }
  
  event void AMSend.sendDone(message_t* msg, error_t error) {
    DBG("send done \n");
  }
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  
  
  event void Timer.fired() {
    cmc_sock_t* sock;
    uint8_t i;
    
    // update the retry_timer of all sockets
    for (i = 0; i < N_SOCKS; i++) {
      sock = &socks[i];
      if (( ((int32_t) sock->retry_timer ) - CMC_PROCESS_TIME) < 0) {
        sock->retry_timer = 0;
      }
      else {
        sock->retry_timer -= CMC_PROCESS_TIME;
      }
      
      switch(sock->com_state) {
        case CMC_PRECONNECTION:
          
          if (sock->retry_timer == 0) {
            // if a timeout occurs
            if (sock->retry_counter < CMC_N_RETRIES) {
              
              // resent sync message
              sock->retry_counter++;
              sock->retry_timer = CMC_RETRY_TIME;
              send_sync(sock, sock->public_key);
              DBG("resending sync message\n");
              return;
              
            }
            else {
              
              // connection attempt failed
              sock->com_state = CMC_CLOSED;
              signal CMC.connected[i](FAIL);
              DBG("a connection attempt has failed\n");
              return;
              
            }
          }
          
          break; /* CMC_PRECONNECTION */
        
        case CMC_ACKPENDING1:
          
          if (sock->retry_timer == 0) {
            if (sock->retry_counter < CMC_N_RETRIES) {
              
              // resend 
              sock->retry_counter++;
              sock->retry_timer = CMC_RETRY_TIME;
              send_data(sock);
              DBG("resending last message\n");
            }
            else {
              
              
            }
          }
          
          break; /* CMC_ACKPENDING1 */
        case CMC_ESTABLISHED:
          
          // TODO: write ack resent thingy
          
          break; /* CMC_ESTABLISHED */
        default:
          //DBG("unknown or unimplemented timeout event occured\n");
          return;
      }
      
    }
    
  }
  
  
  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    
    cmc_hdr_t* packet = payload;
    cmc_sock_t* sock = NULL;
    uint8_t i;
    
    // search for the right socket
    for (i = 0; i < N_SOCKS; i++) {
      
      if (socks[i].group_id == packet->group_id) {
        sock = &socks[i];
        break;
      }      
      
    }
    
    // if socket was not found, continue
    if (sock == NULL) {
      DBG("recv msg, ignored, no socket found with gid: %d\n", socks[i].group_id);
      return msg;
    }
    
    DBG("found socket %d in state %d\n", i, socks[i].com_state);
    
    switch(packet->type) {
      case CMC_SYNC:
        if (IS_SERVER) {
          
          // prepare pointers and metadata for the answer
          uint8_t crypt_err;
          uint8_t answer_size;
          cmc_hdr_t* answer_hdr;
          cmc_key_hdr_t* answer_key_hdr;
          Point remote_public_key;
          
          cmc_sync_hdr_t* sync_hdr = (cmc_sync_hdr_t*) 
            ( (void*) packet + sizeof(cmc_hdr_t) );
          
          
          answer_size = sizeof(cmc_hdr_t) + sizeof(cmc_key_hdr_t);
          
          // decode the public key of the node, that wants to sync
          call ECC.octet2point(&remote_public_key, (uint8_t*) sync_hdr,
            CMC_POINT_SIZE);
          
          // assemble the answer packet
          answer_hdr = (cmc_hdr_t*) (call Packet.getPayload(&pkt, answer_size));
          answer_key_hdr = (cmc_key_hdr_t*) 
            ( (void*) answer_hdr + sizeof(cmc_hdr_t) );
          
          answer_hdr->src_id = sock->local_id;
          answer_hdr->group_id = sock->group_id;
          answer_hdr->dst_id = packet->src_id;
          answer_hdr->type = CMC_KEY;
          
          // encrypt the masterkey with the ecc key from the sync message
          crypt_err = call ECIES.encrypt((uint8_t*) answer_key_hdr, 
            61+CMC_CC_SIZE, (uint8_t*) &(sock->master_key), CMC_CC_SIZE, 
            &remote_public_key);
          DBG("resent data\n");
          call AMSend.send(AM_BROADCAST_ADDR, &pkt, answer_size);
          
          signal CMC.connected[i](SUCCESS);
          
          
          return msg;
          
        }
        else {
          DBG("recv sync msg, but this is not server\n");
          return msg;
        }
        
        break; /* CMC_SYNC */
      
      
      case CMC_KEY:
        
        if (IS_SERVER) {
          DBG("recv key msg, but this is server\n");
          return msg;
        }
        
        if (sock->com_state != CMC_PRECONNECTION) {
          DBG("recv key msgs, but client was not in CMC_PRECONNECTION\n");
          return msg;
        }
        else {
          uint8_t crypt_err;
          cmc_key_hdr_t* key_hdr;
          key_hdr = (cmc_key_hdr_t*) ( (void*) packet + sizeof(cmc_hdr_t) );
          
          // set the server id, which is known by now
          sock->server_id = packet->src_id;
          
          // decrypt and set the masterkey
          crypt_err = call ECIES.decrypt((uint8_t*) &(sock->master_key), CMC_CC_SIZE, 
            (uint8_t*) key_hdr, 61+CMC_CC_SIZE, (sock->private_key));
          
          signal CMC.connected[i](SUCCESS);
          
          DBG("server connect success, got masterkey:");
          print_hex((uint8_t*) &(sock->master_key), 16);
          
          DBG("setting COM_STATE to CONNECTED\n");
          sock->com_state = CMC_ESTABLISHED;
          
          return msg;
        }
        break; /* CMC_KEY */
      
      
      case CMC_DATA:
        
        // check that socket is ok to recevice
        if (sock->com_state == CMC_ESTABLISHED) {
          
          cmc_clear_data_hdr_t decrypted_data;
          uint8_t pad_bytes;
          uint8_t payload_size;
          uint16_t j;
          
          cmc_data_hdr_t* data;
          data = (cmc_data_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t)) ;
          
          DBG("got data from %d to %d\n", packet->src_id, packet->dst_id);
          
          pad_bytes = (CMC_CC_BLOCKSIZE - ((data->length + sizeof(uint16_t) + CMC_HASHSIZE)
          % CMC_CC_BLOCKSIZE) % CMC_CC_BLOCKSIZE);
          
          payload_size = sizeof(uint16_t) + CMC_HASHSIZE + data->length + pad_bytes;
          
          for (j = 0; j < payload_size; j+= CMC_CC_BLOCKSIZE) {
            // decrypt the data, this updates the sockets context as well
            if (call BlockCipher.decrypt(&(sock->master_key),
              ( (uint8_t*) &(data->enc_data)) + j, 
              ( (uint8_t*) &decrypted_data) + j ) != SUCCESS) {
              DBG("error while decryption of recv msg\n");
              return msg;
            }
          }
          
          
          // TODO:check authenticity and integry
          
          memcpy(&(sock->last_msg), &(decrypted_data.data), data->length);
          sock->last_msg_len = data->length;
          sock->last_dst = packet->src_id;
          
          if (IS_SERVER) {
            
            // first try to send data;
            if (send_data(sock)
              != SUCCESS) {
              DBG("error while resending packet as server\n");
              return msg;
            }
            
            // server must go to ACKP2, if unicast, and server is not destination
            if (packet->dst_id != sock->local_id && packet->dst_id != 0xff) {
              sock->com_state = CMC_ACKPENDING2;
            }
            
            // set the retry timer
            sock->retry_counter = 0;
            sock->retry_timer = CMC_RETRY_TIME;
            
          }
          
          // check, wheter you are recipient
          if (packet->dst_id != sock->local_id) {
            DBG("updated cc, returning\n");
            return msg;
          }
          
          else {
            
            /* this part of the code is only reached, if this node is receiver.
             * send ack header to server, not necessary, if you are server
             *  or if you are the sender of the packet */
            if (!(IS_SERVER) && packet->dst_id != 0xff) {
              
              sock->retry_counter = 0;
              sock->retry_timer = CMC_RETRY_TIME;
              
              if (ack_data(sock) != SUCCESS) {
                DBG("error while acking packet\n");
                return msg;
              }
            }
            
            DBG("signal user the message\n");
            /* FIXME: if the user uses send in this block, 
             * the ACK1 of the packet fails, because the if sis busy.
             * I need to introduce some resource management here 
             */
            signal CMC.recv[i](&(decrypted_data.data),
              data->length);
            return msg;
          }
          
        }
        else if (sock->com_state == CMC_ACKPENDING1) {
          
          if (IS_SERVER) {
            DBG("ACKPENDING1 in server should never happen\n");
            return msg;
          }
          else {
            
            //check, whether this is a matching packet resend
            cmc_clear_data_hdr_t decrypted_data;
            CipherContext old_c;
            int payload_size;
            uint16_t j;
            uint8_t pad_bytes;
            
            cmc_data_hdr_t* data;
            data = (cmc_data_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t)) ;
            
            // if packets datalength does not fit, it cant be the right packet
            if (data->length != sock->last_msg_len) {
              DBG("got packet, but length did not match\n");
              return msg;
            }
            
            memcpy(&old_c, &(sock->master_key), sizeof(CipherContext));
            
            pad_bytes = (CMC_CC_BLOCKSIZE - ((data->length + sizeof(uint16_t) +  
              CMC_HASHSIZE) % CMC_CC_BLOCKSIZE) % CMC_CC_BLOCKSIZE);
            
            payload_size = sizeof(uint16_t) + CMC_HASHSIZE + data->length + pad_bytes;
            
            for (j = 0; j < payload_size; j+= CMC_CC_BLOCKSIZE) {
            // decrypt the data, this updates the sockets context as well
              if (call BlockCipher.decrypt(&old_c,
                ( (uint8_t*) &(data->enc_data)) + j, 
                ( (uint8_t*) &decrypted_data) + j ) != SUCCESS) {
                DBG("error while decryption of recv msg\n");
                return msg;
              }
            }
            
            //DBG("dem packets\n");
            //DBG("%s", &decrypted_data.data);
            //DBG("%s", &(sock->last_msg));
            
            if (memcmp(&decrypted_data.data, &(sock->last_msg), sock->last_msg_len) != 0) {
              DBG("this is not the packet we are looking for\n");
              return msg;
            }
            
            DBG("this node got an ACK1\n");
            if (sock->last_dst == sock->server_id) {
              DBG("dst was server, going to ESTABLISHED\n");
              sock->com_state = CMC_ESTABLISHED;
            }
            else {
              DBG("going to ACKPENDING2");
              sock->com_state = CMC_ACKPENDING2;
            }
          
          }
        }
        else {
            DBG("socket was not in condition to receive data\n");
          return msg;
        }
        
        break; /* CMC_DATA */
        
      case CMC_ACK:
        // NOTE: untested
        if (sock->com_state != CMC_ACKPENDING2) {
          DBG("rcvd ACK2, but not in condition\n");
          return msg;
        }
        else {
          
          uint8_t hash[CMC_HASHSIZE];
          cmc_ack_hdr_t* ack_header;
          
          ack_header = (cmc_ack_hdr_t*)( (void*) packet + sizeof(cmc_ack_hdr_t));
          
          if (sha1_hash(hash, &(sock->last_msg), sock->last_msg_len) != SUCCESS) {
            DBG("hashing error in ack2\n");
          return msg;
          }
          
          if (memcmp(hash, &(ack_header->hash), CMC_HASHSIZE) !=0) {
            DBG("got ack, but hash was in correct > ignored\n");
            return msg;
          }
          else {
            DBG("last message was acked\n");
            sock->com_state = CMC_ESTABLISHED;
            return msg;
            // TODO: raise sendDone here?
          }
          
        }
        
        break; /* CMC_ACK */
      
      default:
        DBG("header type %d was not recognized or implemented\n", packet->type);
        return msg;
    }
    
    return msg;
  }
  
  
  
  /* ---------- command implementations ---------- */
  command error_t CMC.init[uint8_t client](uint16_t local_id, 
    NN_DIGIT* private_key, Point* public_key) {
    
    cmc_sock_t* sock = &socks[client];
    
    sock->local_id = local_id;
    
    sock->private_key = private_key;
    sock->public_key = public_key;
    
    return SUCCESS;
    
  }
  
  
  command error_t CMC.bind[uint8_t client](uint16_t group_id) {
    
    uint8_t i;
    uint8_t key[16];
    cmc_sock_t* sock = &socks[client];
    
    #ifdef CMC_CLIENT_ONLY
    return FAIL;
    #endif
    
    // check, that socket is in intial state
    if (sock->sync_state != CMC_CLOSED || sock->com_state != CMC_CLOSED) {
      DBG("error in bind, socket is not in initial state\n");
      return FAIL;
    }
    
    
    sock->group_id = group_id;
    
    // set the client specific fields to self
    sock->server_id = sock->local_id;
    sock->server_public_key = NULL;
    
    DBG("setting socket to LISTEN and ESTABLISHED\n");
    sock->sync_state = CMC_LISTEN;
    sock->com_state = CMC_ESTABLISHED;
    
    // generate Masterkey
    for (i = 0; i < 16; i++) {
      key[i] = call Random.rand16();
    }
    
    if (call BlockCipher.init( &(sock->master_key), 8, 16, key) != SUCCESS) {
            DBG("error while generating masterkey\n");
            return FAIL;
    }
    
    DBG("master key generated:");
    print_hex((uint8_t*)&(sock->master_key), 16);
    
    return SUCCESS;
  }
  
  
  
  command error_t CMC.connect[uint8_t client](uint16_t group_id,
    Point* remote_public_key) {
    
    cmc_sock_t* sock = &socks[client];
    
    DBG("connecting sock: %d\n", client);
    // check, that socket is in intial state
    if (sock->sync_state != CMC_CLOSED || sock->com_state != CMC_CLOSED) {
      DBG("error in connect, socket is not in initial state\n");
      return FAIL;
    }
    
    // set the socket values
    sock->server_public_key = remote_public_key;
    sock->group_id = group_id;
    
    // prepare retry timer for resending SYNC, if this is lost
    sock->retry_counter = 0;
    sock->retry_timer = CMC_RETRY_TIME;
    
    DBG("setting socket to PRECONNECTION\n");
    sock->com_state = CMC_PRECONNECTION;
    
    return send_sync(sock, (sock->public_key));
    
  }
  
  
  
  command error_t CMC.send[uint8_t client](uint16_t dest_id, 
    void* data, uint8_t data_len) {
    
    error_t e;
    cmc_sock_t* sock = &socks[client];
    // copy needed info to socket, needed for resend to be possible
    sock->last_dst = dest_id;
    sock->last_msg_len = data_len;
    
    memcpy(&(sock->last_msg), data, data_len);
    
    
    // first try to send data;
    e = send_data(sock);
    if (e == SUCCESS) {
      DBG("setting COM_STATE to ACKPENDING1\n");
      sock->com_state = CMC_ACKPENDING1;
    }
    
    // set the retry timer, must be done after first attempt
    // or timer could tick, before data was send;
    
    sock->retry_counter = 0;
    sock->retry_timer = CMC_RETRY_TIME;
    
    return e;
  }
  
  
  command error_t CMC.close[uint8_t client]() {
    
  }
  
  
  /* --------- default events -------- */
  default event void CMC.connected[uint8_t cid](error_t e) {}
  
  default event void CMC.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMC.closed[uint8_t cid](uint16_t remote_id, error_t e) {}
  
  default event void CMC.recv[uint8_t cid](void* payload, uint16_t plen) {}
}