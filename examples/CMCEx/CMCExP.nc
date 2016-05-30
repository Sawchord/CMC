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
 
#include <NN.h>
#include <ECC.h>
#include <ECIES.h>
#include <sha1.h>

/* debug output */
#ifdef DEBUG_OUT
#include <printf.h>
#define DBG(...) printf(__VA_ARGS__); printfflush()
#else
#define DBG(...) 
#endif


module CMCExP {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    
    interface CMC as CMC0;
    
    interface Leds;
    
    interface Timer<TMilli>;
    interface LocalTime<TMilli>;
    
    interface Random;
    
    interface NN;
    interface ECC;
    interface ECIES;
    
  }
} implementation {
  
  uint32_t oldtime, newtime;
  
  uint8_t buffer[256];
  
  uint8_t next_node = 0;
  bool sending = FALSE;
  
  
  NN_DIGIT client_priv_key[NUMWORDS];
  NN_DIGIT server_priv_key[NUMWORDS];
  
  Point client_pub_key;
  Point server_pub_key;
  
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
    
    call ECC.gen_private_key(client_priv_key);
    call ECC.gen_private_key(server_priv_key);
    call ECC.gen_public_key(&client_pub_key, client_priv_key);
    call ECC.gen_public_key(&server_pub_key, server_priv_key);
    
    if (TOS_NODE_ID == 1) {
      call CMC0.init(TOS_NODE_ID, server_priv_key, &server_pub_key);
    }
    else {
      call CMC0.init(TOS_NODE_ID, client_priv_key, &client_pub_key);
    }
    
    if (TOS_NODE_ID == 1) {
      call CMC0.bind(1337);
    }
    else {
      call Timer.startPeriodic(5000);
    }
    
    newtime = call LocalTime.get();
    DBG("Socket initialzed after %d ms\n", (newtime - oldtime));
    
    
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  
  event void Timer.fired() {
    DBG("attempt sync\n");
    call CMC0.connect(1337, &server_pub_key);
  }
  
  
  event void CMC0.connected(error_t e) {
    if (e == SUCCESS) {
      call Timer.stop();
      DBG("sync was successfull\n");
    }
  }
  
  event void CMC0.sendDone(error_t e) {
    sending = FALSE;
  }
  
  event void CMC0.closed(uint16_t remote_id, error_t e){
    
  }
  
  event void CMC0.recv(void* payload, uint16_t plen) {
    //call Leds.set((uint8_t) payload);
  }
  
  
}
    