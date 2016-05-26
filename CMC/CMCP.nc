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
  cmc_server_sock_t socks[N_SOCKS];
  
  
  /* --------- helpful functions ---------- */
  
  
  /* sends out a sync message */
  error_t send_sync(cmc_sock_t* sock, Point* pub_key) {
    uint8_t packet_size;
    cmc_hdr_t* packet_hdr;
    cmc_sync_hdr_t* sync_hdr;
    
    // calculate the packet size
    packet_size = sizeof(cmc_hdr_t) + sizeof(cmc_sync_hdr_t);
    
    // set up the packet
    packet_hdr = (cmc_hdr_t*) packet(call Packet.getPayload(&pkt, packet_size))
    sync_hdr = oacket_hdr + sizeof(cmc_hdr_t);
    
    // fill the packet with stuff
    packet_hdr->src_id = sock->local_id;
    packet_hdr->dst_id = destination;
    packet_hdr->group_id = 0x0; // server id is unknown
    
    memcpy( &(packet_hdr->public_key), pub_key, sizeof(Point));
    
    DBG("sync packet assebled\n");
    
    return call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(BlinkToRadioMsg));
    
  }
  
  
  
  
  /* --------- implemented events --------- */
  /* startup initialization */
  command error_t Init.init() {
    uint8_t i;
    
    for (i = 0; i < N_SOCKS; i++) {
      
      // set all sockets to closed
      socks[i].sync_state = CMC_CLOSED;
      socks[i].com_state = CMC_CLOSED;
    }
  }
  
  event void AMSend.sendDone(message_t* msg, error_t error) {
    
  }
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  event void Timer.fired() {
    
  }
  
  
  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    
  }
  
  
  /* ---------- command implementations ---------- */
  command error_t CMC.init[uint8_t client](uint16_t local_id, 
    NN_DIGIT* private_key, Point* public_key) {
    
    cmc_sock_t* sock = socks[client];
    
    sock->local_id = local_id;
    
    sock->private_key = private_key;
    sock->public_key = public_key;
    
  }
  
  
  command error_t CMC.bind[uint8_t client](uint16_t group_id) {
    
    uint8_t i;
    uint8_t key[16];
    cmc_sock_t* sock = socks[client];
    
    // check, that socket is in intial state
    if (sock->sync_state != CMC_CLOSED || sock->com_state != CMC_CLOSED) {
      DBG("error in bind, socket is not in initial state\n");
      return FAIL;
    }
    
    
    sock->group_id = group_id;
    
    // set the client specific fields to self
    sock->server_id = sock->local_id;
    sock->server_public_key = public_key;
    
    DBG("setting socket to LISTEN and ESTABLISHED\n");
    sock->sync_state = CMC_LISTEN;
    sock->com_state = CMC_ESTABLISHED;
    
    // generate Masterkey
    for (i = 0; i < 16; i++) {
      key[i] = call Random.rand8();
    }
    
    if (call BlockCipher.init(&(sock->master_key), 16, 16, key) != SUCCESS) {
            DBG("error while generating masterkey\n");
            return FAIL;
    }
    
    return SUCCESS;
  }
  
  
  
  command error_t CMC.connect[uint8_t client](uint16_t group_id,
    Point* remote_public_key) {
    
    cmc_sock_t* sock = socks[client];
    
    // check, that socket is in intial state
    if (sock->sync_state != CMC_CLOSED || sock->com_state != CMC_CLOSED) {
      DBG("error in connect, socket is not in initial state\n");
      return FAIL;
    }
    
    // set the socket values
    sock->remote_public_key = remote_public_key;
    sock->group_id = group_id;
    
    // prepare retry timer for resendeing SYNC, if this is lost
    sock->retry_counter = 0;
    sock->retry_timer = CMC_RETRY_TIME;
    
    DBG("setting socket to PRECONNECTION\n");
    sock->state = CMC_PRECONNECTION;
    
    send_sync(sock, remote_public_key);
    
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