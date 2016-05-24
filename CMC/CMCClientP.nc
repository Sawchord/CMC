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

#include "crypto/crypto.h"

module CMCClientP {
  provides interface CMCClient[uint8_t client];
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
    N_LOCAL_CLIENTS = uniqueCount("CMC_CLIENT"),
  };
  
  
  /* ------- globals ------- */
  message_t pkt;
  
  /* holds all sockets to cmc in an array */
  cmc_client_sock_t socks[N_LOCAL_CLIENTS];
  
  
  /* --------- implemented events --------- */
  /* startup initialization */
  command error_t Init.init() {
    uint8_t i;
    
    for (i = 0; i < N_LOCAL_CLIENTS; i++) {
      
      // set all sockets to closed
      socks[i].state = CMC_CLOSED;
    }
    
  }
  
  
  /* start the timer */
  event void Boot.booted() {
    call Timer.startPeriodic(CMC_PROCESS_TIME);
  }
  
  event void Timer.fired() {
    
  }
  
  event void AMSend.sendDone(message_t* msg, error_t error) {
    
  }
  
  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
    
  }
  
  /* ---------- command implementations ---------- */
  command error_t CMCClient.init[uint8_t client](uint16_t local_id,
    void* buf, uint16_t buf_len, cmc_keypair_t* local_key) {
    
    cmc_client_sock_t* sock = &socks[client];
    
    // set all local parameters
    sock->state = CMC_CLOSED;
    sock->local_id = local_id;
    
    sock->buf = buf;
    sock->buf_len = buf_len;
    
    // TODO: instead of pointer to ecc_key, generate key structure here
    sock->key = local_key;
    
  }
  
  
  command error_t CMCClient.connect[uint8_t client](uint16_t group_id,
    Point* remote_public_key) {
    
    
    cmc_hdr_t* main_header;
    cmc_sync_hdr_t* sync_header;
    
    // set the global parameters
    cmc_client_sock_t* sock = &socks[client];
    sock->group_id = group_id;
    
    sock->state = CMC_PRECONNECTION;
    
    main_header = (cmc_hdr_t*)(call Packet.getPayload(&pkt, 
      sizeof(main_header) + sizeof(sync_header)));
    
    sync_header = main_header + sizeof(main_header);
    
    main_header->src = sock->local_id;
    main_header->dst = group_id;
    main_header->flags = (1 << CMC_SYNC);
    
    memcpy( &(sync_header->public_key), remote_public_key, sizeof(Point) );
    
    return (call AMSend.send(AM_CMC, &pkt, sizeof(main_header) + sizeof(sync_header)) );
    
  }
  
  
  command error_t CMCClient.send[uint8_t client](uint16_t id,
    void* data, uint16_t data_len) {
    
    
  }
  
  
  command error_t CMCClient.close[uint8_t client]() {
    
  }
  
  
  /* --------- default events -------- */
  default event void CMCClient.connected[uint8_t cid](error_t e) {}
  
  default event void CMCClient.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMCClient.closed[uint8_t cid](error_t e) {}
  
  default event void CMCClient.recv[uint8_t cid](void* payload, uint16_t plen) {}
}