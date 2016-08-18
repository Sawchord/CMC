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
  
  /* This bool must be set, whenever a
   * call to AMSend.send is made, to prevent
   * other parts of the program try to use 
   * the Radio while its busy.
   */
  bool interface_busy = FALSE;
  
  /* Sometimes, a function needs to do something
   * after already sending something. If this requires
   * sending, it can not be done directly, since the
   * interface is still busy. This bool is set, to
   * indicate, that something still need to be done,
   * the next time, the interface comes out of busy.
   */
  bool interface_callback = FALSE;
  
  /* Point this to the last socket, that used
   * the interface
   */
  cmc_sock_t* last_busy_sock;
  
  /* Holds the message type, of the last send msg. */
  uint8_t last_send_msg_type;
  
  /* Holds all sockets to cmc servers in an array */
  cmc_sock_t socks[N_SOCKS];
  
  
  /* --------- helpful functions ---------- */
  
  
  /* Sends out a sync message */
  error_t send_sync(cmc_sock_t* sock, Point* pub_key) {
    
    uint8_t packet_size;
    cmc_hdr_t* packet_hdr;
    cmc_sync_hdr_t* sync_hdr;
    
    if (interface_busy == TRUE) {
      DBG("send_sync failed, busy interface\n");
      return FAIL;
    }
    
    // Calculate the packet size
    packet_size = sizeof(cmc_hdr_t) + sizeof(cmc_sync_hdr_t);
    
    // Set up the packet
    packet_hdr = (cmc_hdr_t*)(call Packet.getPayload(&pkt, packet_size));
    
    // Calculate the sync_header pointer by offsetting
    sync_hdr = (cmc_sync_hdr_t*) ( (void*) packet_hdr + sizeof(cmc_hdr_t) );
    
    // Fill the packet with stuff
    packet_hdr->src_id = sock->local_id;
    packet_hdr->dst_id = 0xff; // since the servers id is unknown of now
    packet_hdr->group_id = sock->group_id;
    
    // NOTE: If you leave this out, it still works, but it should not
    packet_hdr->type = CMC_SYNC;
    
    // fill in the public key of the server
    call ECC.point2octet((uint8_t*) &(sync_hdr->public_key), 
      CMC_POINT_SIZE, pub_key, FALSE);
    
    interface_busy = TRUE;
    last_busy_sock = sock;
    last_send_msg_type = CMC_SYNC;
    
    DBG("sync send\n");
    return call AMSend.send(AM_BROADCAST_ADDR, &pkt, packet_size);
    
  }
  
  /* Generates a simple sha1 hash of a message */
  error_t sha1_hash(void* output, void* input, uint16_t input_len) {
    SHA1Context ctx;
    error_t err;
    err = call SHA1.reset(&ctx);
    err = call SHA1.update(&ctx, input, input_len);
    err = call SHA1.digest(&ctx, output);
    return err;
  }
  
  
  
  error_t send_data(cmc_sock_t* sock) {
    
    cmc_hdr_t* message_hdr;
    cmc_data_hdr_t* data_header;
    
    cmc_clear_data_hdr_t clear_data;
    
    uint8_t message_size; /* size of the complete message including main header */
    uint8_t payload_size; /* actual size of the data field */
    uint8_t pad_bytes;
    uint16_t i;
    uint8_t data_len;
    
    if (interface_busy == TRUE) {
      DBG("busy if\n");
      return FAIL;
    }
    
    data_len = sock->last_msg_len;
    
    // calculate the number of padding bytes needed
    pad_bytes = (CMC_CC_BLOCKSIZE - ( (data_len + sizeof(uint16_t) + CMC_HASHSIZE)
      % CMC_CC_BLOCKSIZE) % CMC_CC_BLOCKSIZE);
    
    DBG("data_len:%d pad_bytes:%d\n", data_len, pad_bytes);
    
    // check for the right conditions to send
    if ( !(sock->com_state == CMC_ESTABLISHED || sock->com_state == CMC_ACKPENDING1) ) {
      DBG("socket not in condition to send\n");
      return FAIL;
    }
    
    if (data_len + pad_bytes > CMC_DATAFIELD_SIZE) {
      DBG("data too long\n");
      return FAIL;
    }
    
    // calculate size
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
    
    //DBG("Calculated message hash:");
    //print_hex(&(clear_data.hash), CMC_HASHSIZE);
    
    // prepare the message to send
    message_hdr = (cmc_hdr_t*)(call Packet.getPayload(&pkt, message_size));
    data_header = (cmc_data_hdr_t*)( (void*) message_hdr + sizeof(cmc_hdr_t) );
    
    DBG("payload_size: %d pad_bytes: %d \n", payload_size, pad_bytes);
    
    message_hdr->src_id = sock->local_id;
    message_hdr->group_id = sock->group_id;
    message_hdr->dst_id = sock->last_dst;
    message_hdr->type = CMC_DATA;
    
    data_header->length = data_len;
    
    /* 
     * Encrypt the data.
     * The blockchipher encryption must be called multiple
     * times, since it does not have its own loop.
     * This results in this ugly pointer arithmetic.
     */
    for (i = 0; i < payload_size; i += CMC_CC_BLOCKSIZE) {
      if (call BlockCipher.encrypt(&(sock->master_key), 
        ((uint8_t*) &clear_data) + i, ((uint8_t*) &(data_header->enc_data)) + i ) 
        != SUCCESS) {
        DBG("error in send while encrypting\n");
        return FAIL;
      }
    }
    
    
    interface_busy = TRUE;
    last_busy_sock = sock;
    last_send_msg_type = CMC_DATA;
    
    //DBG("send_data: %s\n", sock->last_msg);
    DBG("send_data\n");
    if  (call AMSend.send(AM_BROADCAST_ADDR, &pkt, message_size) != SUCCESS) {
      DBG("error sending data\n");
      return FAIL;
    }
    
    return SUCCESS;
    
    
  } /* send_data */
  
  
  
  error_t ack_data(cmc_sock_t* sock) {
    // NOTE: untested
    cmc_hdr_t* ack_header;
    cmc_ack_hdr_t* ack_field;
    
    uint8_t ack_size;
    
    if (interface_busy == TRUE) {
      DBG("ack_data failed, busy interface\n");
      return FAIL;
    }
    
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
    
    //DBG("calculated hash:");
    //print_hex(ack_field->hash, CMC_HASHSIZE);
    
    interface_busy = TRUE;
    interface_callback = TRUE;
    last_busy_sock = sock;
    last_send_msg_type = CMC_ACK;
    
    if (call AMSend.send(AM_BROADCAST_ADDR, &pkt, ack_size) != SUCCESS) {
      DBG("error while sending ack");
      return FAIL;
    }
    
    DBG("acked data\n");
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
  
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  
  event void AMSend.sendDone(message_t* msg, error_t error) {
    
    cmc_sock_t* sock = last_busy_sock;
    uint8_t last_busy_sock_num;
    
    if (interface_busy != TRUE) {
      DBG("send done risen with not busy interface -> bug.\n");
    }
    interface_busy = FALSE;
    
    // quit, if nothing needs to be done
    if (interface_callback == FALSE) {
      DBG("send done\n");
      return;
    }
    interface_callback = FALSE;
    
    last_busy_sock_num = (uint8_t) ((void*) last_busy_sock - (void*) sock);
    
    
    switch (last_send_msg_type) {
      
      case CMC_SYNC:
        break; /* CMC_SYNC */
        
      case CMC_KEY:
        break; /* CMC_KEY */
        
      case CMC_DATA:
        
        DBG("signal user the message\n");
        signal CMC.recv[last_busy_sock_num]
          (&(sock->last_msg), sock->last_msg_len);
        
        break; /* CMC_DATA */
        
      case CMC_ACK:
        
        DBG("signal user the message\n");
        signal CMC.recv[last_busy_sock_num]
          (&(sock->last_msg), sock->last_msg_len);
        
        break; /* CMC_ACK */
      
      default:
        DBG("sendDone risen without last_send_msg_type set -> bug");
        break;
      
      
    }
    
  }
  
  
  event void Timer.fired() {
    cmc_sock_t* sock;
    uint8_t i;
    
    // Update the retry_timer of all sockets
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
              DBG("a connection attempt has failed\n");
              signal CMC.connected[i](FAIL);
              return;
              
            }
          }
          
          break; /* CMC_PRECONNECTION */
        
        
        /* The server needs to behave in ACKPENDING2
         * as a client node in ACKPENDING1.
         * The following creates a switch falltrough,
         * but only, if the node is a server.
         */
        //case CMC_ACKPENDING2:
        //  if (!IS_SERVER) break;
        
        case CMC_ACKPENDING1:
          
          if (sock->retry_timer == 0) {
            if (sock->retry_counter < CMC_N_RETRIES) {
              
              // resend the message
              sock->retry_counter++;
              sock->retry_timer = CMC_RETRY_TIME;
              send_data(sock);
              DBG("resending last message\n");
            }
            else {
              
              // send attempt attempt failed
              sock->com_state = CMC_CLOSED;
              DBG("sending the message has failed\n");
              signal CMC.sendDone[i](FAIL);
              return;
              
            }
          }
          
          break; /* CMC_ACKPENDING1 */
        
        
         /* This part handles the resending of the ACK packet
          * on the receiving node.
          */
        case CMC_ESTABLISHED:
          /*
          if (sock->retry_timer == 0) {
            if (sock->retry_counter < CMC_N_RETRIES) {
              
              sock->retry_counter++;
              sock->retry_timer = CMC_RETRY_TIME;
              DBG("");
              
              return;
            }
            else {
              
              
              
            }
          }
          */
          break; /* CMC_ESTABLISHED */
        default:
          return;
      }
      
      
    }
    // TODO: go back into initial states, after timeout 
    // (right now, only the senders go back)
    
    return;
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
    
    DBG("recv packet for socket %d in state %d\n", i, socks[i].com_state);
    
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
          
          DBG("recv sync msg\n");
          
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
          
          interface_busy = TRUE;
          last_busy_sock = sock;
          last_send_msg_type = CMC_KEY;
          
          
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
          
          /* The old master_key needs to be saved,
           * since it may be necessary to revert to it
           * if the integrity or authenticity check fails.
           */
          NN_DIGIT old_master_key;
          
          uint8_t hash[CMC_HASHSIZE];
          
          cmc_data_hdr_t* data;
          data = (cmc_data_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t)) ;
          
          DBG("got data from %d to %d\n", packet->src_id, packet->dst_id);
          
          pad_bytes = (CMC_CC_BLOCKSIZE - ((data->length + sizeof(uint16_t) + CMC_HASHSIZE)
          % CMC_CC_BLOCKSIZE) % CMC_CC_BLOCKSIZE);
          
          payload_size = sizeof(uint16_t) + CMC_HASHSIZE + data->length + pad_bytes;
          
          // Save masterkey
          memcpy(&old_master_key, &(sock->master_key), sizeof(NN_DIGIT));
          
          for (j = 0; j < payload_size; j+= CMC_CC_BLOCKSIZE) {
            // decrypt the data, this updates the sockets context as well
            if (call BlockCipher.decrypt(&(sock->master_key),
              ( (uint8_t*) &(data->enc_data)) + j, 
              ( (uint8_t*) &decrypted_data) + j ) != SUCCESS) {
              DBG("error while decryption of recv msg\n");
              return msg;
            }
          }
          
          
          // Check authenticity
          if (decrypted_data.group_id != sock->group_id) {
            DBG("Gids not matching, packet forged\n");
            DBG("recvd gid: %d, socks gid: %d", decrypted_data.group_id, sock->group_id);
            
            // revert key
            memcpy(&(sock->master_key), &old_master_key, sizeof(NN_DIGIT));
            return msg;
          }
          
          // Check integrity
          if (sha1_hash(hash, &(decrypted_data.data), 
            (data->length + pad_bytes)) != SUCCESS) {
            
            DBG("hashing error while checking integrity\n");
          return msg;
          }
          if (memcmp(hash, decrypted_data.hash, CMC_HASHSIZE) != 0) {
            DBG("Hashes are not matching, integrity fail\n");
            //DBG("Received hash:");
            //print_hex(&(decrypted_data.hash), CMC_HASHSIZE);
            
            //DBG("Calculated hash:");
            //print_hex(hash, CMC_HASHSIZE);
            
            // revert key
            memcpy(&(sock->master_key), &old_master_key, sizeof(NN_DIGIT));
            return msg;
          }
          
          
          
          memcpy(&(sock->last_msg), &(decrypted_data.data), data->length);
          sock->last_msg_len = data->length;
          sock->last_dst = packet->src_id;
          
          if (IS_SERVER) {
            
            // first try to resend data, step 2 of protocoll
            interface_callback = TRUE;
            if (send_data(sock) != SUCCESS) {
              DBG("error while resending packet as server\n");
              interface_callback = FALSE;
              return msg;
            }
            
            // server must go to ACKP2, if not unicast, and server is not destination
            if (packet->dst_id != sock->local_id && packet->dst_id != 0xff) {
              sock->com_state = CMC_ACKPENDING2;
            }
            
            // set the retry timer
            sock->retry_counter = 0;
            sock->retry_timer = CMC_RETRY_TIME;
            
          }
          
          // check, whether you are recipient
          if (packet->dst_id != sock->local_id) {
            DBG("updated cc, returning\n");
            return msg;
          }
          
          else {
            
            /* This part of the code is only reached, if this node is receiver.
             * send ack header to server, not necessary, if you are server
             *  or if you are the sender of the packet */
            if (!(IS_SERVER) && packet->dst_id != 0xff) {
              
              if (ack_data(sock) != SUCCESS) {
                DBG("error while acking packet\n");
                return msg;
              }
              
              sock->retry_counter = 0;
              sock->retry_timer = CMC_RETRY_TIME;
              
            }
              
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
            
            /* If packets datalength does not fit, 
             * it cant be the right packet and we 
             * can return right away.
             */
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
            
            
            if (memcmp(&decrypted_data.data, &(sock->last_msg), 
              sock->last_msg_len) != 0) {
              DBG("this is not the packet we are looking for\n");
              return msg;
            }
            
            DBG("this node got an ACK1\n");
            if (sock->last_dst == sock->server_id) {
              DBG("dst was server, going to ESTABLISHED\n");
              sock->com_state = CMC_ESTABLISHED;
            }
            else {
              DBG("going to ACKPENDING2\n");
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
        // TODO: Check for correct destination and source ids?
        if (sock->com_state != CMC_ACKPENDING2) {
          DBG("rcvd ACK2, but not in condition\n");
          return msg;
        }
        else {
          
          uint8_t hash[CMC_HASHSIZE];
          cmc_ack_hdr_t* ack_header;
          
          ack_header = (cmc_ack_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t));
          
          if (sha1_hash(hash, &(sock->last_msg), sock->last_msg_len) != SUCCESS) {
            DBG("hashing error in ack2\n");
          return msg;
          }
          
          //DBG("hash comparison:");
          //print_hex(hash, CMC_HASHSIZE);
          //print_hex(ack_header->hash, CMC_HASHSIZE);
          
          if (memcmp(hash, &(ack_header->hash), CMC_HASHSIZE) !=0) {
            DBG("got ack, but hash was incorrect > ignored\n");
            return msg;
          }
          else {
            DBG("last message was acked, going to ESTABLISHED\n");
            sock->com_state = CMC_ESTABLISHED;
            return msg;
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
    
    // TODO: Better set server_public_key to client_private_key??
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
    
    DBG("setting socket to PRECONNECTION\n");
    sock->com_state = CMC_PRECONNECTION;
    
    if  (send_sync(sock, (sock->public_key)) != SUCCESS) {
      sock->com_state = CMC_CLOSED;
      return FAIL;
    }
    else {
      
      // prepare retry timer for resending SYNC, if this is lost
      sock->retry_counter = 0;
      sock->retry_timer = CMC_RETRY_TIME;
      
      return SUCCESS;
    }
    
  }
  
  
  
  command error_t CMC.send[uint8_t client](uint16_t dest_id, 
    void* data, uint8_t data_len) {
    
    error_t err;
    cmc_sock_t* sock = &socks[client];
    
    // if node addresses itself, make simple pointer handling out of it
    if (sock->local_id == dest_id) {
      signal CMC.recv[client](data, data_len);
    }
    
    // copy needed info to socket, needed for resend to be possible
    sock->last_dst = dest_id;
    sock->last_msg_len = data_len;
    
    memcpy(&(sock->last_msg), data, data_len);
    
    
    // first try to send data;
    err = send_data(sock);
    if (err == SUCCESS) {
      if (IS_SERVER) {
        DBG("setting COM_STATE to ACKPENDING2, because this is a server\n");
        sock->com_state = CMC_ACKPENDING2;
      }
      else {
        DBG("setting COM_STATE to ACKPENDING1\n");
        sock->com_state = CMC_ACKPENDING1;
      }
    }
    
    /* Set the retry timer, must be done after first attempt
     * or timer could tick, before data was send;
     */
    sock->retry_counter = 0;
    sock->retry_timer = CMC_RETRY_TIME;
    
    return err;
  }
  
  
  command error_t CMC.close[uint8_t client]() {
    
  }
  
  
  /* --------- default events -------- */
  default event void CMC.connected[uint8_t cid](error_t e) {}
  
  default event void CMC.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMC.closed[uint8_t cid](uint16_t remote_id, error_t e) {}
  
  default event void CMC.recv[uint8_t cid](void* payload, uint16_t plen) {}
}
