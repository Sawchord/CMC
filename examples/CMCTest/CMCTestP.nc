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

#include <CMC.h>

/* debug output */
#if(1)
#include <printf.h>
#define OUT(...) printf(__VA_ARGS__); printfflush()
#else
#define OUT(...) 
#endif


module CMCTestP {
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
    
    interface SHA1;
    
    interface Read<uint8_t> as LightRead;
    interface Read<uint16_t> as TempRead;
    
  }
} implementation {
  
  uint32_t oldtime, newtime;
  
  bool sending = FALSE;
  bool connected = FALSE;
  bool connecting = FALSE;
  
  SensorMsg send_msg;
  SensorMsg* recv_msg;
  
  
  NN_DIGIT private_key[NUMWORDS];
  
  Point public_key;
  
  event void Boot.booted() {
    oldtime = call LocalTime.get();
    
    // Start the radio interface
    call RadioControl.start();
    
  }
  
  
  event void RadioControl.startDone(error_t e) {
    
    //char hash_output[20];
    
    if (e != SUCCESS) {
      OUT("error starting radio... retry\n");
      call RadioControl.start();
      return;
    }
    
    newtime = call LocalTime.get();
    OUT("Radio is up after %d ms\n", (newtime - oldtime));
    oldtime = newtime;
    
    
    //call ECC.gen_private_key(private_key);
    
    // TODO: Find method to load a private key
    call ECC.gen_public_key(&public_key, private_key);
    
    // Initialze the CMC interface
    call CMC0.init(TOS_NODE_ID, private_key, &public_key);
    
    // Node 1 becomes the server with group id 1234
    if (TOS_NODE_ID == 1) {
      call CMC0.bind(1234);
    }
    
    // The other nodes start their main operation
    if (TOS_NODE_ID != 1) {
      call Timer.startPeriodic(1000);
    }
    
    newtime = call LocalTime.get();
    OUT("Socket initialized after %d ms\n", (newtime - oldtime));
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  event void CMC0.connected(error_t e) {
    
    connecting = FALSE;
    
    if (e == SUCCESS) {
      newtime = call LocalTime.get();
      OUT("sync was successfull after %d ms\n", (newtime - oldtime));
      oldtime = newtime;
      connected = TRUE;
    }
    else {
      OUT("connection\n");
    }
  }
  
  event void CMC0.sendDone(error_t e) {
    OUT("Send done was signaled\n");
    sending = FALSE;
  }
  
  event void CMC0.closed(uint16_t remote_id, error_t e){
    
  }
  
  event void CMC0.recv(void* payload, uint16_t plen) {
    
    if (TOS_NODE_ID == 1) {
      OUT("Server does nothing\n");
      return;
    }
    else if (TOS_NODE_ID == 2) {
      
      // This is where the other nodes ask for a led bitmask
      
      
    }
    else {
      
    }
    
  }
  
  event void Timer.fired() {
    
    
  }
  
  
  event void LightRead.readDone(error_t err, uint8_t lum) {
    
  }
  
  event void TempRead.readDone(error_t err, uint16_t lum) {
    
  }
  
}
    