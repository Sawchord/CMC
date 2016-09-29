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
    
    interface OCBMode;
    
    interface NN;
    interface ECC;
    interface ECIES;

    #ifdef BENCHMARK
      interface LocalTime<TMilli>;
    #endif
    
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
  
  /* Some computationally intensive parts 
   * should not be scheduled twice
   */
  //bool sync_busy = FALSE;
  
  /* Point this to the last socket, that used
   * the interface
   */
  cmc_sock_t* last_busy_sock;
  
  /* Holds the message type, of the last send msg. */
  uint8_t last_send_msg_type;
  
  /* Holds all sockets to cmc servers in an array */
  cmc_sock_t socks[N_SOCKS];
  
#ifdef BENCHMARK
  uint32_t timer;
#endif
  
  /* Sends out a sync message */
  error_t send_sync(cmc_sock_t* sock, Point* pub_key) {
    
    uint8_t packet_size;
    cmc_hdr_t* packet_hdr;
    cmc_sync_hdr_t* sync_hdr;
    
    if (interface_busy == TRUE) {
      DBG("[send_sync] failed, busy if\n");
      return FAIL;
    }
    
    #ifdef BENCHMARK
      timer = call LocalTime.get();
    #endif
    
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
    
    #ifdef BENCHMARK
      BENCH("[senc_sync] [bench] sending sync: %u ms\n", (call LocalTime.get() - timer));
    #endif
    
    DBG("[send_sync] success\n");
    return call AMSend.send(AM_BROADCAST_ADDR, &pkt, packet_size);
    
  }
  
  
  error_t send_data(cmc_sock_t* sock) {
    
    cmc_hdr_t* message_hdr;
    cmc_data_hdr_t* data_header;
    
    // The context needed for the OCBMode encryption
    CipherModeContext context;
    
    uint8_t message_size; /* size of the complete message including main header */
    uint8_t payload_size; /* actual size of the data field */
    uint8_t data_len;
    
    if (interface_busy == TRUE) {
      DBG("[send_data] failed, busy if\n");
      return FAIL;
    }
    
    #ifdef BENCHMARK
      timer = call LocalTime.get();
    #endif
    
    data_len = sock->last_msg_len;
    
    // check for the right conditions to send
    if ( !(sock->com_state == CMC_ESTABLISHED ) ) {
      DBG("[send_data] not in condition to send\n");
      return FAIL;
    }
    
    if (data_len + CMC_CC_SIZE > CMC_DATAFIELD_SIZE) {
      DBG("[send_data] data too long\n");
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
    
    DBG("[send_data] payload_size: %u, data_len: %u\n", payload_size, data_len);
    
    message_hdr->src_id = sock->local_id;
    message_hdr->group_id = sock->group_id;
    message_hdr->dst_id = sock->last_dst;
    message_hdr->type = CMC_DATA;
    
    data_header->length = data_len;
    
    // encrypt the data
    // initialze the context
    if (call OCBMode.init(&context, CMC_CC_SIZE, sock->master_key) != SUCCESS) {
      DBG("[send_data] error in OCB init\n");
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
      DBG("[send_data] OCB encryption error\n");
      return FAIL;
    }
    
    // load the updated counter back into the socket
    sock->ccounter = call OCBMode.get_counter(&context);
    
    
    interface_busy = TRUE;
    last_busy_sock = sock;
    last_send_msg_type = CMC_DATA;
    
    #ifdef BENCHMARK
      BENCH("[send_data] [bench] sending data: %u ms\n", (call LocalTime.get() - timer));
    #endif
    
    if (call AMSend.send(AM_BROADCAST_ADDR, &pkt, message_size) != SUCCESS) {
      DBG("[send_data] send failed\n");
      return FAIL;
    }
    
    DBG("[send_data] success\n");
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
    return SUCCESS;
  }
  
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  
  event void AMSend.sendDone(message_t* msg, error_t error) {
    
    //cmc_sock_t* sock = last_busy_sock;
    
    uint8_t last_busy_sock_num;
    
    // Calculate the number of the last busy socket
    // out of the socks pointer and the poiner to the last
    // busy sock, since the TinyOS generics need the number
    // and not the pointer. 
    last_busy_sock_num = (uint8_t) ((void*) last_busy_sock - (void*) socks);
    
    if (interface_busy != TRUE) {
      DBG("[sendDone] risen but no busy interface -> bug.\n");
    }
    interface_busy = FALSE;
    
    // TODO: Change this behaviour to something sensible
    
    if (last_send_msg_type == CMC_DATA) {
      DBG("[sendDone] signal to user\n");
      signal CMC.sendDone[last_busy_sock_num](SUCCESS);
    }
    else {
       //DBG("interface_callback set, but pkt send was not data -> bug\n");
    }
    
    return;
    
  }
  
  
  event void Timer.fired() {
    cmc_sock_t* sock;
    uint8_t i;
    
    // Update the retry_timer of all sockets
    for (i = 0; i < N_SOCKS; i++) {
      sock = &socks[i];
      
      // If the timer is already zero, it is not in use
      if (sock->retry_timer == 0) continue;
      
      if (( ((int32_t) sock->retry_timer ) - CMC_PROCESS_TIME) < 0) {
        sock->retry_timer = 0;
      }
      else {
        sock->retry_timer -= CMC_PROCESS_TIME;
      }
      
      if (sock->retry_timer == 0) {
        
        switch(sock->com_state) {
          case CMC_PRECONNECTION:
            
            // if a timeout occurs
            if (sock->retry_counter < CMC_N_RETRIES) {
              
              // resent sync message
              sock->retry_counter++;
              sock->retry_timer = CMC_RETRY_TIME;
              send_sync(sock, &sock->public_key);
              DBG("[timeout] resending sync message\n");
              return;
              
            }
            else {
              
              // connection attempt failed
              sock->com_state = CMC_CLOSED;
              DBG("[timeout] a connection attempt has failed\n");
              signal CMC.connected[i](FAIL, 0);
              return;
              
            }
            
            break; /* CMC_PRECONNECTION */
          
          default:
            return;
        }
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
      //DBG("ign recv msg, no sock with gid: %u\n", socks[i].group_id);
      return msg;
    }
    
    //FIXME: There is a bug here, sometimes node crashes and restarts here
    //DBG("recv pkt %u for sock %u in state %u\n", packet->type, i, socks[i].com_state);
    
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
          
          DBG("[recv_sync] msg\n");
          
          // why does this not work?
          /*atomic {
            if (sync_busy == TRUE) {
              DBG("recv_sync rejected: busy\n");
              return msg;
            }
            sync_busy = TRUE;
          }*/
          
          #ifdef BENCHMARK
            timer = call LocalTime.get();
          #endif
          
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
          
          
          DBG("[recv_sync] send key data\n");
          call AMSend.send(AM_BROADCAST_ADDR, &pkt, answer_size);
          
          // NOTE: No retry timers to set. If key msg is lost, node will resend sync message.
          
          //atomic {sync_busy = FALSE;}
          
          #ifdef BENCHMARK
            BENCH("[recv_sync] [bench] recv sync: %u ms\n", (call LocalTime.get() - timer));
          #endif
          
          signal CMC.connected[i](SUCCESS, packet->src_id);
          
          return msg;
          
        }
        else {
          DBG("[recv_sync] not server -> ignore\n");
          return msg;
        }
        
        break; /* CMC_SYNC */
      
      case CMC_KEY:
        
        if (IS_SERVER) {
          DBG("[recv_key] this is server -> ignore\n");
          return msg;
        }
        
        if (sock->com_state != CMC_PRECONNECTION) {
          DBG("[recv_key] not in CMC_PRECONNECTION -> ignore\n");
          return msg;
        }
        else {
          uint8_t crypt_err;
          cmc_key_hdr_t* key_hdr;
          
          uint8_t j;
          
          #ifdef BENCHMARK
            timer = call LocalTime.get();
          #endif
          
          key_hdr = (cmc_key_hdr_t*) ( (void*) packet + sizeof(cmc_hdr_t) );
          
          // decrypt and set the masterkey
          crypt_err = call ECIES.decrypt((uint8_t*) &(sock->master_key), CMC_CC_SIZE, 
            (uint8_t*) key_hdr, 61+CMC_CC_SIZE, (sock->private_key));
          
          DBG("[recv_key] connect success, masterkey:");
          print_hex((uint8_t*) &(sock->master_key), 16);
          
          // Since no two counter of a network are allowed to use the same counter
          // Every node uses its local_id as the first two bytes in the counter
          sock->ccounter_compound[3] = sock->local_id;
          
          for (j = 0; j < 3; j++) {
            sock->ccounter_compound[j] = call Random.rand16();
          }
          
          DBG("[recv_key] generated counter:");
          print_hex(&sock->ccounter, 8);
          
          DBG("[recv_key] setting COM_STATE to ESTABLISHED\n");
          sock->com_state = CMC_ESTABLISHED;
          
          #ifdef BENCHMARK
            BENCH("[recv_key] [bench] revc key and generating counter: %u ms\n", (call LocalTime.get() - timer));
          #endif
          
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
          
          int last_busy_sock_num;
          
          error_t err;
          
          cmc_data_hdr_t* data;
          
          #ifdef BENCHMARK
            timer = call LocalTime.get();
          #endif
          
          data = (cmc_data_hdr_t*)( (void*) packet + sizeof(cmc_hdr_t)) ;
          
          DBG("[recv_data] from %u to %u\n", packet->src_id, packet->dst_id);
          
          if (packet->dst_id != sock->local_id && packet->dst_id != 0xffff) {
            DBG("[recv_data] not this node -> ignore\n");
            return msg;
          }
          
          //             data length    counter            length
          payload_size = data->length + sizeof(uint64_t) + sizeof(uint16_t);
          
          // do the decryption
          // initialze the context
          if (call OCBMode.init(&context, CMC_CC_SIZE, sock->master_key) != SUCCESS) {
            DBG("[revc_data] error in OCB init\n");
            return msg;
          }
          
          // set the counter
          ccounter = data->ccounter;
          call OCBMode.set_counter(&context, ccounter);
          
          
          DBG("[recv_data] decrypting with counter:");
          print_hex(&ccounter, 8);
          
          sock->last_msg_len = data->length;
  
          sock->last_dst = packet->src_id;
          
          DBG("[recv_data] data length:%u\n", sock->last_msg_len);
          
          // do the actual decryption
          if ((err = call OCBMode.decrypt(&context, sock->last_msg, NULL, (uint8_t*) data->data,
          sock->last_msg_len, 0, sock->last_msg_len + CMC_CC_SIZE, NULL)) != SUCCESS) {
            DBG("[recv_data] error in OCB decrypt\n");
            //DBG("error: %u\n", err);
            return msg;
          }
          
          
          // No need to get the counter back, it wont be used anymore
          
          last_busy_sock = sock;
          
          last_busy_sock_num = (uint8_t) ((void*) sock - (void*) socks);
          
          #ifdef BENCHMARK
            BENCH("[recv_data] [bench] decrypting data: %u ms\n", (call LocalTime.get() - timer));
          #endif
          
          signal CMC.recv[last_busy_sock_num] 
            (&(sock->last_msg), sock->last_msg_len, 0);
          
          return msg;
            
          
        } // end of the ESTABLISHED part
        else {
          DBG("[recv_data] not in condition to receive data\n");
          return msg;
        }
        break; /* CMC_DATA */
      
      default:
        DBG("[recv] header type %u not recognized \n", packet->type);
        return msg;
    }
    
    return msg;
  }
  
  
  
  /* ---------- command implementations ---------- */
  command error_t CMC.init[uint8_t client](uint16_t local_id, 
    NN_DIGIT* private_key) {
    
    cmc_sock_t* sock = &socks[client];
    
    sock->local_id = local_id;
    
    sock->private_key = private_key;
    
    call ECC.gen_public_key(&sock->public_key, private_key);
    //sock->public_key = public_key;
    
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
      DBG("[bind] socket not in init state\n");
      return FAIL;
    }
    
    // The server always has the nodeid 0
    sock->local_id = 0;
    
    sock->group_id = group_id;
    
    DBG("[bind] going to LISTEN and ESTABLISHED\n");
    sock->sync_state = CMC_LISTEN;
    sock->com_state = CMC_ESTABLISHED;
    
    // generate Masterkey
    // FIXME: is it realy necessary to go in one steps?
    for (i = 0; i < 16; i++) {
      key[i] = call Random.rand16();
    }
    
    // Generate ccounter
    sock->ccounter_compound[3] = sock->local_id;
    
    for (i = 0; i < 3; i++) {
      sock->ccounter_compound[i] = call Random.rand16();
    }
    
    DBG("[bind] generated counter:");
    print_hex(&sock->ccounter, 8);
    
    // FIXME: If this works, one might to be able to generate it directly in this field
    memcpy(&sock->master_key, &key, 16);
    
    DBG("[bind] master key generated:");
    print_hex((uint8_t*)&(sock->master_key), 16);
    
    return SUCCESS;
  }
  
  
  
  command error_t CMC.connect[uint8_t client](uint16_t group_id) {
    cmc_sock_t* sock = &socks[client];
    
    DBG("[connect] sock: %u\n", client);
    // check, that socket is in intial state
    if (sock->sync_state != CMC_CLOSED || sock->com_state != CMC_CLOSED) {
      DBG("[connect] socket not in init state\n");
      return FAIL;
    }
    
    // set the socket values
    sock->group_id = group_id;
    
    DBG("[connect] going to PRECONNECTION\n");
    sock->com_state = CMC_PRECONNECTION;
    
    if  (send_sync(sock, &(sock->public_key)) != SUCCESS) {
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
      return err;
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
