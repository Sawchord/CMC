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

module CMCServerP {
  provides interface CMCServer[uint8_t client];
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
    N_LOCAL_SERVERS = uniqueCount("CMC_SERVER"),
  };
  
  /* holds all sockets to cmc servers in an array */
  cmc_server_sock_t socks[N_LOCAL_SERVERS];
  
  /* --------- implemented events --------- */
  /* startup initialization */
  command error_t Init.init() {
    uint8_t i;
    
    for (i = 0; i < N_LOCAL_SERVERS; i++) {
      
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
  command error_t CMCServer.init[uint8_t client](uint16_t local_id,
    void* buf, uint16_t buf_len, cmc_keypair_t* local_key) {
    
    
    int i = 0;
    
    cmc_server_sock_t* sock = &socks[client];
    
    sock->state = CMC_CLOSED;
    sock->local_id = local_id;
    
    sock->asym_key = local_key;
    
    
    // initialize all connections to an initial state
    for(i = 0; i < CMC_MAX_CLIENTS; i++) {
      sock->connection[i].remote_id = 0xffff;
      sock->connection[i].state = CMC_CLOSED;
    }
    
  }
  
  
  command error_t CMCServer.bind[uint8_t client](uint16_t group_id) {
    //TODO:generate master key
    cmc_server_sock_t* sock = &socks[client];
    sock->group_id = group_id;
    
    sock->state = CMC_LISTEN;
    
  }
  
  
  command error_t CMCServer.send[uint8_t client](uint16_t id, 
    void* data, uint16_t data_len) {
    
  }
  
  
  command error_t CMCServer.close[uint8_t client](uint16_t remote_id) {
    
  }
  
  command error_t CMCServer.shutdown[uint8_t client]() {
    
  }
  
  /* --------- default events -------- */
  default event void CMCServer.connected[uint8_t cid](error_t e) {}
  
  default event void CMCServer.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMCServer.closed[uint8_t cid](uint16_t remote_id, error_t e) {}
  
  default event void CMCServer.recv[uint8_t cid](void* payload, uint16_t plen) {}
}