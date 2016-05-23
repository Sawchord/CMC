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


module CMCServerExP {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    
    interface CMCServer as Server0;
    
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
  
  uint8_t buffer[1024];
  
  bool connected = FALSE;
  bool connecting = FALSE;
  bool sending = FALSE;
  
  cmc_keypair_t client_key;
  cmc_keypair_t server_key;
  
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
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  
  event void Timer.fired() {
    if (!connected && !connecting) {
      oldtime = call LocalTime.get();
      DBG("Sending out me data\n");
      
      return;
    }
  }
  
  
  event void Server0.connected(error_t e) {
    
  }
  
  event void Server0.sendDone(error_t e) {
    sending = FALSE;
  }
  
  event void Server0.closed(error_t e){
    connected = FALSE;
  }
  
  event void Server0.recv(void* payload, uint16_t plen) {
    call Leds.set((uint8_t) payload);
  }
  
  
}
    