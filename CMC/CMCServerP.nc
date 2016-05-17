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

module CMCServerP {
  provides interface CMCServer[uint8_t client];
  provides interface Init;
  uses {
    interface Boot;
    interface Timer<TMilli>;
    
    interface Random;
    
    uses interface Packet;
    uses interface AMSend;
    uses interface Receive;
  }
} implementation {
  
  enum {
    N_LOCAL_SERVERS = uniqueCount("CMC_SERVER");
  };
  
  /* holds all sockets to cmc servers in an array */
  cmc_server_sock_t[N_LOCAL_SERVERS];CMCCLientP
  
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
  
  /* ---------- command implementations ---------- */
  command error_t CMCServerP.init[uint8_t client](uint16_t local_id,
    void* buf, uint16_t buf_len) {
    
  }
  
  
  command error_t CMCServerP.bind[uint8_t client](uint16_t group_id,
    ecc_key* local_public_key) {
    
  }
  
  
  command error_t CMCServerP.send[uint8_t client](void* data, uint16_t data_len) {
    
  }
  
  
  command error_t CMCServerP.close[uint8_t client]() {
    
  }
  
  commant error_t CMCServerP.shutdown[client]() {
    
  }
  
  /* --------- default events -------- */
  default event void CMCServerP.connected[uint8_t cid](error_t e) {}
  
  default event void CMCServerP.sendDone[uint8_t cid](error_t e) {}
  
  default event void CMCServerP.closed[uint8_t cid](error_t e) {}
  
  default event void CMCServerP.recv[uint8_t cid](error_t e) {}
}