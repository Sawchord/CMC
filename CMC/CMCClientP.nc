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

#include "tinypkc/ecc.h"
#include "tinypkc/integer.h"


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
    
  }
} implementation {
  
  enum {
    N_LOCAL_CLIENTS = uniqueCount("CMC_CLIENT"),
  };
  
  /* holds all sockets to cmc in an array */
  cmc_client_sock_t socks[N_LOCAL_CLIENTS];
  
  
  /* --------- implemented events --------- */
  /* startup initialization */
  command error_t Init.init() {
    
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
    void* buf, uint16_t buf_len, ecc_key* local_key) {
    
  }
  
  
  command error_t CMCClient.connect[uint8_t client](uint16_t group_id,
    ecc_key* remote_public_key) {
    
  }
  
  
  command error_t CMCClient.send[uint8_t client](void* data, uint16_t data_len) {
    
  }
  
  
  command error_t CMCClient.close[uint8_t client]() {
    
  }
  
  
  /* --------- default events -------- */
  default event void CMCClient.connected[uint8_t cid](error_t e) {}
  
  default event void CMCClient.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMCClient.closed[uint8_t cid](error_t e) {}
  
  default event void CMCClient.recv[uint8_t cid](void* payload, uint16_t plen) {}
}