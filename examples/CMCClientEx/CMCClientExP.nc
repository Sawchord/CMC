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

// TODO: includes

#include <tinypkc/ecc.h>
#include <tinypkc/integer.h>

/* debug output */
#ifdef DEBUG_OUT
#include <printf.h>
#define DBG(...) printf(__VA_ARGS__); printfflush()
#else
#define DBG(...) 
#endif


module CMCClientExP {
uses {
  interface Boot;
  interface SplitControl as RadioControl;
  
  interface CMCClient as Client0;
  
  interface Leds;
  
  interface Timer<TMilli>;
  interface LocalTime<TMilli>;
  
  interface Random;
  
  interface ECC;
  
  }
} implementation {
  
  /* --------- globals --------*/
  // these variables are used for benchmarking
  uint32_t oldtime, newtime;
  
  uint8_t buffer[1024];
  
  bool connected = FALSE;
  bool connecting = FALSE;
  bool sending = FALSE;
  
  mp_digit  local_key_buff[4* MP_PREC];
  ecc_key   local_key;
  mp_digit  remote_key_buf[4* MP_PREC];
  ecc_key   remote_key;
  
  event void Boot.booted() {
    oldtime = call LocalTime.get();
    // start the radio
    call RadioControl.start();
    
  }
  
  event void RadioControl.startDone(error_t e) {
    
    if (e != SUCCESS) {
      DBG("error starting radio... retry\n");
      call RadioControl.start();
      return;
    }
    
    
    newtime = call LocalTime.get();
    DBG("Radio is up after %d ms\n", (newtime - oldtime));
    
    // after the radio is up, initialze the local key, which is needed for the Client init
    
    oldtime = newtime;
    call ECC.init_key(local_key_buff, 4 * MP_PREC, &local_key);
    call ECC.import_private_key(MY_ECC_PRIVATE, MY_ECC_PRIVATE_LEN, 
      MY_ECC_PUBLIC, MY_ECC_PUBLIC_LEN, &local_key);
    
    
    call ECC.init_key(remote_key_buf, 4 * MP_PREC, &remote_key);
    call ECC.import_x963(OTHER_ECC_PUBLIC, OTHER_ECC_PUBLIC_LEN, &remote_key);
    
    call Client0.init(TOS_NODE_ID, &buffer, 1024, &local_key);
    
    newtime = call LocalTime.get();
    DBG("Client socket initialzed after %d ms\n", (newtime - oldtime));
    
    call Timer.startPeriodic(2000);
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  event void Timer.fired() {
    if (!connected && !connecting) {
      oldtime = call LocalTime.get();
      DBG("Attempting to connect to server\n");
      
      connecting = TRUE;
      call Client0.connect(1, &remote_key.pubkey);
      return;
    }
  }
  
  event void Client0.connected(error_t e) {
    
    if (e != SUCCESS) {
      // if connection was not successfull, just try again
      DBG("connect attempt failed\n");
      connecting = FALSE;
    }
    else {
      connecting = FALSE;
      connected = TRUE;
      
      newtime = call LocalTime.get();
      DBG("successfully connected after %d ms\n", (newtime - oldtime) );
    }
    
  }
  
  event void Client0.sendDone(error_t e) {
    sending = FALSE;
  }
  
  event void Client0.closed(error_t e){
    connected = FALSE;
  }
  
  event void Client0.recv(void* payload, uint16_t plen) {
    call Leds.set((uint8_t) payload);
  }
  
}