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
    packet_hdr = (cmc_hdr_t*)(call Packet.getPayload(&pkt, 29));
    
    // calculate the sunc_header pointer by offsetting
    sync_hdr = (cmc_sync_hdr_t*) ( (void*) packet_hdr + sizeof(cmc_hdr_t));
    
    // fill the packet with stuff
    packet_hdr->src_id = sock->local_id;
    packet_hdr->dst_id = 0xff; // since the servers id is unknown of now
    packet_hdr->group_id = sock->group_id;
    
    
    // fill in the public key of the server
    call ECC.point2octet((uint8_t*) &(sync_hdr->public_key), 
      CMC_POINT_SIZE, pub_key, FALSE);
    
    //DBG("sync packet assembled:");
    //print_hex((uint8_t*) &(sync_hdr->public_key), 42);
    //DBG("out of pub_key");
    //print_hex((uint8_t*) pub_key, 42);
    
    return call AMSend.send(AM_BROADCAST_ADDR, &pkt, packet_size);
    
  }
  
  
  
  
  /* --------- implemented events --------- */
  /* startup initialization */
  command error_t Init.init() {
    uint8_t i;
    
    //call ECC.init();
    
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
    
  }
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  event void Timer.fired() {
    cmc_sock_t* sock;
    uint8_t i;
    
    //DBG("process timer tick @%d ms\n", CMC_PROCESS_TIME);
    
    // update the retry_timer of all sockets
    for (i = 0; i < N_SOCKS; i++) {
      sock = &socks[i];
      if (( (int32_t) sock->retry_timer - CMC_PROCESS_TIME) < 0) {
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
              send_sync(sock, sock->server_public_key);
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
        //DBG("found socket %d\n", i);
        continue;
      }      
      
    }
    
    // if socket was not found, continue
    if (sock == NULL) {
      DBG("recv msg, ignored, no socket found\n");
      return msg;
    }
    
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
          
          // answer the sync packet with a key packet
          //DBG("receviced sync packet:");
          //print_hex((uint8_t*) &(sync_hdr->public_key), 42);
          
          
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
          
          // --- debug -- delete later
          /*DBG("encryption: %d\n", crypt_err);
          //DBG("packet=%p  sync_hdr=%p, answer_hdr=%p, answer_key_hdr=%p\n",
            //packet, sync_hdr, answer_hdr, answer_key_hdr);
          
          DBG("remote pub key:");
          print_hex((uint8_t*) &remote_public_key, 42);
          
          DBG("encrypted context looks like:");
          print_hex((uint8_t*) answer_key_hdr, 61+CMC_CC_SIZE);
          
          memset( &(sock->master_key), 0,  16);
          
          crypt_err = call ECIES.decrypt((uint8_t*) &(sock->master_key), CMC_CC_SIZE, 
            (uint8_t*) answer_key_hdr, 61+CMC_CC_SIZE, (sock->private_key));
          
          DBG("decryption: %d\n", crypt_err);
          DBG("encrypt decrypt loop:");
          print_hex((uint8_t*) &(sock->master_key), 16);
          */
          // -- end of debug -- delete later
          
          call AMSend.send(AM_BROADCAST_ADDR, &pkt, answer_size);
          
          signal CMC.connected[i](SUCCESS);
          
          //DBG("answered sync packet:");
          //print_hex((uint8_t*) answer_key_hdr, 61+CMC_CC_SIZE);
          
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
          
          // set the server id, which is now know
          sock->server_id = packet->src_id;
          
          //DBG("The encrypted context is:");
          //print_hex((uint8_t*) (key_hdr->encrypted_context), 61+CMC_CC_SIZE);
          
          // decrypt and set the masterkey
          crypt_err = call ECIES.decrypt((uint8_t*) &(sock->master_key), CMC_CC_SIZE, 
            (uint8_t*) key_hdr, 61+CMC_CC_SIZE, (sock->private_key));
          
          //DBG("decryption: %d\n", crypt_err);
          signal CMC.connected[i](SUCCESS);
          
          DBG("server connect success, got masterkey:");
          print_hex((uint8_t*) &(sock->master_key), 16);
          
          DBG("setting COM_STATE to CONNECTED\n");
          sock->com_state = CMC_ESTABLISHED;
          
          return msg;
        }
        break; /* CMC_KEY */
      
      case CMC_DATA: /* CMC_DATA */
        break;
        
      case CMC_ACK:
        break; /* CMC_ACK */
      
      default:
        DBG("header type %d was not recognized or implemented\n", packet->type);
        return msg;
    }
    
    
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
  
  
  
  command error_t CMC.send[uint8_t client](uint16_t id, 
    void* data, uint16_t data_len) {
    
  }
  
  
  command error_t CMC.close[uint8_t client]() {
    
  }
  
  
  /* --------- default events -------- */
  default event void CMC.connected[uint8_t cid](error_t e) {}
  
  default event void CMC.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMC.closed[uint8_t cid](uint16_t remote_id, error_t e) {}
  
  default event void CMC.recv[uint8_t cid](void* payload, uint16_t plen) {}
}