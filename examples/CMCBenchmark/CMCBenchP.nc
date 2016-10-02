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

#if(1)
#include <printf.h>
#define OUT(...) printf(__VA_ARGS__); printfflush()
#else
#define OUT(...) 
#endif


module CMCBenchP {
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
    
    
    interface SHA1;
  }
} implementation {
  
  uint32_t oldtime, newtime;
  
  bool sending = FALSE;
  bool connected = FALSE;
  bool connecting = FALSE;
  
  NN_DIGIT client_priv_key[NUMWORDS];
  NN_DIGIT server_priv_key[NUMWORDS];
  
  uint8_t test_n = 0;
  uint8_t test_state = 0;
  uint64_t localtime = 0;
  
  event void Boot.booted() {
    oldtime = call LocalTime.get();
    
    // start radio (must be done manually)
    call RadioControl.start();
    
  }
  
  
  event void RadioControl.startDone(error_t e) {
    
    if (e != SUCCESS) {
      OUT("error starting radio... retry\n");
      call RadioControl.start();
      return;
    }
    
    call ECC.gen_private_key(client_priv_key);
    call ECC.gen_private_key(server_priv_key);
    
    if (TOS_NODE_ID == 1) {
      call CMC0.init(TOS_NODE_ID, server_priv_key);
    }
    else {
      call CMC0.init(TOS_NODE_ID, client_priv_key);
    }
    
    if (TOS_NODE_ID == 1) {
      call CMC0.bind(1337);
    }
    else {
      test_n = 1;
      test_state = 1;
      localtime = call LocalTime.get();
      
      call CMC0.connect_add_data(1337, &test_n, 1);
    }
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  void gen_ran(uint8_t length, void* ptr) {  
    
    uint8_t i;
    
    if (length % 2 != 0) {
      return;
    }
    
    for (i = 0; i < length; i+= 2) {
       ((uint8_t*)ptr)[i] = call Random.rand16();
    }
    
  }
  
  event void Timer.fired() {
    uint8_t some_data[100];
    error_t e;
    
    test_state += 2;
    if (test_n == 2) {
      gen_ran(test_n, (void*) &some_data);
      some_data[0] = test_n;
      //OUT("[test2] %u bytes\n", test_state);
      e = call CMC0.send(0xffff, (void*) &some_data, test_state);
      if (e != SUCCESS) {
        OUT("[test2] error %u b\n", test_state);
      }
      
      if (test_state == 100) {
        test_n = 3;
        test_state = 0;
      }
      
    }
    
    
    
  }
  
  
  event void CMC0.connected(error_t e, uint16_t nodeid) {
    
    if (TOS_NODE_ID == 1) {
      return;
    }
    
    if (e != SUCCESS) {
      OUT("[test1] connection err\n");
      return;
    }
    
    if (test_n == 1 && test_state == 1) {
      OUT("[test1] %u ms\n", (unsigned int) (call LocalTime.get() - localtime));
      
      test_n = 2;
      test_state = 0;
      call Timer.startPeriodic(25);
      
    }
    
  }
  
  event void CMC0.sendDone(error_t e) {
    if (e != SUCCESS) {
      OUT("[sendDone] error");
      return;
    }
    
    if (test_n == 2) {
      return;
    }
    
    
  }
  
  
  event void CMC0.recv(void* payload, uint16_t plen, uint16_t nodeid) {
    if ( *((uint8_t*)payload) == 2) {
      return;
    }
    
    
  }
  
  event bool CMC0.accept(uint16_t node_id, Point* remote_public_key, uint8_t* add_data, uint8_t add_data_len) {
    if (*add_data == 1) {
      return TRUE;
    }
    else {
      OUT("[accept] data did not match\n");
      return FALSE;
    }
  }
  
}
    
