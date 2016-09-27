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


// New vresion v0.3.0

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
    
    //interface BlockCipher;
    interface OCBMode;
    
    interface NN;
    interface ECC;
    interface ECIES;
    
    interface SHA1;
    
    // Debug
    interface Leds;
    
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
  
  //uint8_t ledstatus = 0;
  /* --------- debug functions ---------*/
  void incled() {
    if (TOS_NODE_ID == 1) call Leds.set(call Leds.get() + 1);
  }
  
  /* --------- helpful functions ---------- */
  
  
  /* Sends out a sync message */
  error_t send_sync(cmc_sock_t* sock, Point* pub_key) {
    
    uint8_t packet_size;
    cmc_hdr_t* packet_hdr;
    cmc_sync_hdr_t* sync_hdr;
    
    if (interface_busy == TRUE) {
      DBG("send_sync failed, busy if\n");
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
  /*error_t sha1_hash(void* output, void* input, uint16_t input_len) {
    SHA1Context ctx;
    error_t err;
    err = call SHA1.reset(&ctx);
    err = call SHA1.update(&ctx, input, input_len);
    err = call SHA1.digest(&ctx, output);
    return err;
  }*/
  
  
  error_t send_data(cmc_sock_t* sock) {
    
    cmc_hdr_t* message_hdr;
    cmc_data_hdr_t* data_header;
    
    // The context needed for the OCBMode encryption
    CipherModeContext context;
    
    uint8_t message_size; /* size of the complete message including main header */
    uint8_t payload_size; /* actual size of the data field */
    uint8_t data_len;
    
    if (interface_busy == TRUE) {
      DBG("data send failed, busy if\n");
      return FAIL;
    }
    
    data_len = sock->last_msg_len;
    
    // check for the right conditions to send
    if ( !(sock->com_state == CMC_ESTABLISHED || sock->com_state == CMC_ACKPENDING) ) {
      DBG("socket not in condition to send\n");
      return FAIL;
    }
    
    if (data_len + CMC_CC_SIZE > CMC_DATAFIELD_SIZE) {
      DBG("data too long\n");
      return FAIL;
    }
    
    // calculate size
    //             data       encyption takes 16 bytes
    payload_size = data_len + CMC_CC_SIZE;
    //             header              encrypted data  counter             length field
    message_size = sizeof(cmc_hdr_t) + payload_size +  sizeof(uint64_t) + sizeof(uint16_t);
    
    
    
    // prepare the message to send
    message_hdr = (cmc_hdr_t*)(call Packet.getPayload(&pkt, message_size));
    data_header = (cmc_data_hdr_t*)( (void*) message_hdr + sizeof(cmc_hdr_t) );
    
    DBG("payload_size: %d, data_len: %d\n", payload_size, data_len);
    
    message_hdr->src_id = sock->local_id;
    message_hdr->group_id = sock->group_id;
    message_hdr->dst_id = sock->last_dst;
    message_hdr->type = CMC_DATA;
    
    data_header->length = data_len;
    
    // encrypt the data
    
    // initialze the context
    if (call OCBMode.init(&context, CMC_CC_SIZE, sock->master_key) != SUCCESS) {
      DBG("error in OCBMode.init in send_data\n");
      return FAIL;
    }
    
    // set the current counter.
    // this must be done now, since it will be changed later
    data_header->ccounter = sock->ccounter;
    
    // Set the counter into the context.
    call OCBMode.set_counter(&context, sock->ccounter);
    
    DBG("encypting with counter:");
    print_hex(&sock->ccounter, 8);
    
    // do the actual encryption
    if (call OCBMode.encrypt(&context, sock->last_msg, NULL, (uint8_t*) data_header->data,
      data_len, 0, sock->last_msg_len + CMC_CC_SIZE, NULL) != SUCCESS){
      DBG("encryption error in send_data\n");
      return FAIL;
    }
    
    // load the updated counter back into the socket
    sock->ccounter = call OCBMode.get_counter(&context);
    
    
    interface_busy = TRUE;
    last_busy_sock = sock;
    last_send_msg_type = CMC_DATA;
    
    DBG("send data\n");
    if  (call AMSend.send(AM_BROADCAST_ADDR, &pkt, message_size) != SUCCESS) {
      DBG("error sending data\n");
      return FAIL;
    }
    
    return SUCCESS;
    
  } /* send_data */
  
  
  /* --------- implemented events --------- */
  // startup initialization 
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
    
    //NOTE: Output here makes the whole node crash fatally
    //DBG("CMC init complete\n");
    incled();
    return SUCCESS;
  }
  
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  
  event void AMSend.sendDone(message_t* msg, error_t error) {
    
    cmc_sock_t* sock = last_busy_sock;
    uint8_t last_busy_sock_num;
    
    // Calculate the number of the last busy socket
    // out of the socks pointer and the poiner to the last
    // busy sock, since the TinyOS generics need the number
    // and not the pointer. 
    last_busy_sock_num = (uint8_t) ((void*) last_busy_sock - (void*) socks);
    
    if (interface_busy != TRUE) {
      DBG("sendDone risen no busy interface -> bug.\n");
    }
    interface_busy = FALSE;
    
    // quit, if nothing needs to be done
    if (interface_callback == FALSE) {
      DBG("send done on sock %d\n", last_busy_sock_num);
      
      // NOTE: From the user side, a send done happens, if an ACK was received
      // and not here. This send done just denotes, that one half of the protocol
      // has finished.
      
      return;
    }
    interface_callback = FALSE;
    
    
    if (last_send_msg_type == CMC_DATA) {
      DBG("signal msg to user\n");
        signal CMC.recv[last_busy_sock_num]
          (&(sock->last_msg), sock->last_msg_len, sock->last_dst);
    }
    else {
       DBG("interface_callback set, but pkt send was not data -> bug\n");
    }
    return;
    
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
              signal CMC.connected[i](FAIL, 0);
              return;
              
            }
          }
          
          break; /* CMC_PRECONNECTION */
        
        
        case CMC_ACKPENDING:
          
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
          
          break; /* CMC_ACKPENDING */
        
         /* This part handles the resending of the ACK packet
          * on the receiving node.
          */
        case CMC_ESTABLISHED:
          break; /* CMC_ESTABLISHED */
        default:
          return;
      }
      
    }
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
      DBG("ign recv msg, no sock with gid: %d\n", socks[i].group_id);
      return msg;
    }
    
    //FIXME: There is a bug here, sometimes node crashes and restarts here
    //DBG("sp at %p\n", &i);
    //incled();
    DBG("recv pkt %d for sock %d in state %d\n", packet->type, i, socks[i].com_state);
    incled();
    
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
          
          
          DBG("send key data\n");
          call AMSend.send(AM_BROADCAST_ADDR, &pkt, answer_size);
          
          // NOTE: No retry timers to set. If key msg is lost, node will resend sync message.
          
          signal CMC.connected[i](SUCCESS, packet->src_id);
          
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
          
          uint8_t j;
          
          key_hdr = (cmc_key_hdr_t*) ( (void*) packet + sizeof(cmc_hdr_t) );
          
          // decrypt and set the masterkey
          crypt_err = call ECIES.decrypt((uint8_t*) &(sock->master_key), CMC_CC_SIZE, 
            (uint8_t*) key_hdr, 61+CMC_CC_SIZE, (sock->private_key));
          
          DBG("server connect success, got masterkey:");
          print_hex((uint8_t*) &(sock->master_key), 16);
          
          // Need to generate ccounter here
          
          // cast ccounter to uint16_t pointer, to fill it with rand16 values
          //ccounter_ptr =  (uint16_t*) &sock->ccounter;
          
          // Since no two counter of a network are allowed to use the same counter
          // Every node uses its local_id as the first two bytes in the counter
          sock->ccounter_compound[3] = sock->local_id;
          
          for (j = 0; j < 3; j++) {
            sock->ccounter_compound[j] = call Random.rand16();
          }
          
          
          DBG("Generated counter:");
          print_hex(&sock->ccounter, 8);
          
          DBG("setting COM_STATE to ESTABLISHED\n");
          sock->com_state = CMC_ESTABLISHED;
          
          // NOTE: This was moved down. Check for bugs.
          // Signal user, that the node is now connected to server
          signal CMC.connected[i](SUCCESS, 0);
          
          return msg;
        }
        break; /* CMC_KEY */
      
      
      case CMC_DATA:
        
        // check that socket is ok to recevice
        if (sock->com_state == CMC_ESTABLISHED) {
          
          CipherModeContext context;
          uint8_t payload_size;
          uint64_t ccounter;
          
          cmc_data_hdr_t* data;
          data = (cmc_data_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t)) ;
          
          incled();
          
          DBG("got data from %d to %d\n", packet->src_id, packet->dst_id);
          
          // server checks, if dst_id is 0. If this happens
          // there is another server using the same group id in reach
          if (IS_SERVER && packet->dst_id != 0) {
            DBG("Another server with same gid in reach\n");
            return msg;
          }
          
          // if node is not server, don't process sgs that do not come from the server
          if (!IS_SERVER && packet->src_id != 0) {
            DBG("rcvd message from other client, ignored\n");
            return msg;
          }
          
          //             data length    counter            length
          payload_size = data->length + sizeof(uint64_t) + sizeof(uint16_t);
          
          incled();
          
          // do the decryption
          // initialze the context
          if (call OCBMode.init(&context, CMC_CC_SIZE, sock->master_key) != SUCCESS) {
            DBG("error in OCBMOde.init in CMC_DATA processing\n");
            return msg;
          }
          
          // set the counter
          ccounter = data->ccounter;
          call OCBMode.set_counter(&context, ccounter);
          
          
          DBG("decrypting with counter:");
          print_hex(&ccounter, 8);
          
          sock->last_msg_len = data->length;
  
          sock->last_dst = packet->src_id;
          
          DBG("data length:%d\n", sock->last_msg_len);
          
          // do the actual decryption
          if (call OCBMode.decrypt(&context, sock->last_msg, NULL, (uint8_t*) data->data,
          sock->last_msg_len, 0, sock->last_msg_len + CMC_CC_SIZE, NULL) != SUCCESS) {
            DBG("Error while decrypting in CMC_DATA ESTABLISHED.\n");
            return msg;
          }
          
          incled();
          
          // No need to get the counter back, it wont be used anymore
          
          // NOTE: Maybe this is to general, and the assignment 
          // should be somewere down there.
          last_busy_sock = sock;
          
          // If this is a server, it needs to resent the message
          // then signal the user. Note that a server does not reach
          // this code, if the message had another dst_id than 0.
          // If this is a client, it only needs to resent and signal
          // the message, if it is the receiver.
          // If its mutlicast, it only needs to signal the message,
          // but not resend it.
          if (IS_SERVER || (!IS_SERVER && packet->dst_id == sock->local_id)) {
            
            incled();
            
            // activate interface callback mechanism and send the data
            interface_callback = TRUE;
            if (send_data(sock) != SUCCESS) {
              DBG("error while acking data\n");
              interface_callback = FALSE;
              //incled();
              return msg;
            }
            
            incled();
            
            // NOTE: Retry Timers needed?
            
            // NOTE: Node stays in CMC_ESTABLISHED
            
            // FIXME: This node is able to recover, if you leave this out???
            //return msg;
          }
          // The broadcast
          else if (!IS_SERVER && packet->dst_id == 0xFF) {
            int last_busy_sock_num;
            
            last_busy_sock_num = (uint8_t) ((void*) sock - (void*) socks);
            
            incled();
            
            DBG("recvd broadcast msg\n");
            signal CMC.recv[last_busy_sock_num] 
              (&(sock->last_msg), sock->last_msg_len, 0);
            
            incled();
            
            return msg;
            
          }
          
          // Not server and not client recipient
          else {
            DBG("updated cipher context, returning\n");
            return msg;
          }
          
        } // end of the ESTABLISHED part
        else if (sock->com_state == CMC_ACKPENDING) {
          
          // Ugly mem consumptytion here, yikes
          uint8_t decrypted_message[CMC_DATAFIELD_SIZE];
          //check, whether this is a matching packet resend
          CipherModeContext context;
          int payload_size;
          uint64_t ccounter;
          
          // calculate the socket number instead of pointer
          uint8_t active_sock_num;
          
          cmc_data_hdr_t* data;
          data = (cmc_data_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t)) ;
          
          // If packets datalength does not fit, 
          // it cant be the right packet and we 
          // can return right away.
          if (data->length != sock->last_msg_len) {
            DBG("got packet, but length did not match\n");
            return msg;
          }
          
          
          payload_size = data->length + sizeof(uint64_t) + sizeof(uint16_t);
          
          // do the decryption
          // initialze the context
          if (call OCBMode.init(&context, CMC_CC_SIZE, sock->master_key) != SUCCESS){
            DBG("Error in OCBMode.init in ACK\n");
            return msg;
          }
          
          // set the counter
          ccounter = data->ccounter;
          call OCBMode.set_counter(&context, ccounter);
          
          
          DBG("decrypting with counter:");
          print_hex(&ccounter, 8);
          
          // do the actual decryption
          if (call OCBMode.decrypt(&context, decrypted_message, NULL, (uint8_t*) data->data,
          data->length, 0, data->length + CMC_CC_SIZE, NULL) != SUCCESS) {
            DBG("Error while decrypting in CMC_DATA in ACKPENDING.\n");
            return msg;
          }
          
          
          if (memcmp(&decrypted_message, &(sock->last_msg), 
            sock->last_msg_len) != 0) {
            DBG("ACK packet was not matching\n");
            return msg;
          }
          
          DBG("Got acked, setting COM_STATE to ESTABLISHED\n");
          sock->com_state = CMC_ESTABLISHED;
          
          // From the users perspective, this is when a send was successfull, 
          // thus sendDone must be signaled here.
          
          active_sock_num = (uint8_t) ((void*) sock - (void*) socks);
          signal CMC.sendDone[active_sock_num](SUCCESS);
          
          return msg;
        }
        else {
          DBG("socket was not in condition to receive data\n");
          return msg;
        }
        
        DBG("dont come here\n");
        break; /* CMC_DATA */
      
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
    
    // The server always has the nodeid 0
    sock->local_id = 0;
    
    sock->group_id = group_id;
    
    DBG("setting socket to LISTEN and ESTABLISHED\n");
    sock->sync_state = CMC_LISTEN;
    sock->com_state = CMC_ESTABLISHED;
    
    // generate Masterkey
    // FIXME: is it realy necessary to go in one steps?
    for (i = 0; i < 16; i++) {
      key[i] = call Random.rand16();
    }
    
    /*if (call BlockCipher.init( &(sock->master_key), 8, 16, key) != SUCCESS) {
      DBG("error while generating masterkey\n");
      return FAIL;
    }*/
    
    // FIXME: If this works, one might to be able to generate it directly in this field
    memcpy(&sock->master_key, &key, 16);
    
    DBG("master key generated:");
    print_hex((uint8_t*)&(sock->master_key), 16);
    
    return SUCCESS;
  }
  
  
  
  command error_t CMC.connect[uint8_t client](uint16_t group_id) {
    cmc_sock_t* sock = &socks[client];
    
    DBG("connecting sock: %d\n", client);
    // check, that socket is in intial state
    if (sock->sync_state != CMC_CLOSED || sock->com_state != CMC_CLOSED) {
      DBG("error in connect, socket is not in initial state\n");
      return FAIL;
    }
    
    // set the socket values
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
    
    // Only server can send to another machine than the server.
    if (!IS_SERVER) {
      dest_id = 0;
    }
    
    // If a node addresses itself, 
    // make simple pointer handling out of it.
    // This can only happen to the server, 
    // since all other nodes can only send to server.
    if (sock->local_id == dest_id) {
      signal CMC.recv[client](data, data_len, sock->local_id);
    }
    
    // copy all infor about send into socket,
    // needed for resend to be possible
    sock->last_dst = dest_id;
    sock->last_msg_len = data_len;
    
    memcpy(&(sock->last_msg), data, data_len);
    
    
    // first try to send data;
    err = send_data(sock);
    if (err == SUCCESS) {
      
      DBG("setting COM_STATE to ACKPENDING\n");
      sock->com_state = CMC_ACKPENDING;
      
    }
    
    // Set the retry timer, must be done after first attempt
    // or timer could tick, before data was send;
    sock->retry_counter = 0;
    sock->retry_timer = CMC_RETRY_TIME;
    
    return err;
  }
  
  
  /* --------- default events -------- */
  default event void CMC.connected[uint8_t cid](error_t e, uint16_t nodeid) {}
  
  default event void CMC.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMC.recv[uint8_t cid](void* payload, uint16_t plen, uint16_t nodeid) {}
}
