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
//#ifdef DEBUG_OUT
#if(1)
#include <printf.h>
#define OUT(...) printf(__VA_ARGS__); printfflush()
#else
#define OUT(...) 
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
    
    interface SHA1;
  }
} implementation {
  
  uint32_t oldtime, newtime;
  
  bool sending = FALSE;
  bool connected = FALSE;
  bool connecting = FALSE;
  
  char teststr[] = "Some secret message nobody should now.\n";
  char teststr2[] = "Some really secret answer.\n";
  
  NN_DIGIT client_priv_key[NUMWORDS];
  NN_DIGIT server_priv_key[NUMWORDS];
  
  Point client_pub_key;
  Point server_pub_key;
  
  event void Boot.booted() {
    oldtime = call LocalTime.get();
    // start the radio
    
    // start radio (must be done manually)
    call RadioControl.start();
    
  }
  
  void sha1_hash(void* output, void* input, uint16_t input_len) {
    SHA1Context ctx;
    call SHA1.reset(&ctx);
    call SHA1.update(&ctx, input, input_len);
    call SHA1.digest(&ctx, output);
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
    
    /*oldtime = newtime;
    sha1_hash(&hash_output, &teststr, 4);
    newtime = call LocalTime.get();
    OUT("hashtest took %d ms and result:", (newtime - oldtime));
    print_hex(&hash_output, 20);
    */
    
    // after the radio is up
    //initialze the local key, which is needed for the Client init
    
    oldtime = newtime;
    
    call ECC.gen_private_key(client_priv_key);
    call ECC.gen_private_key(server_priv_key);
    call ECC.gen_public_key(&client_pub_key, client_priv_key);
    call ECC.gen_public_key(&server_pub_key, server_priv_key);
    
    /*
    OUT("client priv key:");
    print_hex((uint8_t*)client_priv_key, NUMWORDS);
    OUT("client pub key:");
    print_hex((uint8_t*)&client_pub_key, 42);
    OUT("server priv key:");
    print_hex((uint8_t*)server_priv_key, NUMWORDS);
    OUT("server pub key:");
    print_hex((uint8_t*)&server_pub_key, 42);
    */
    
    if (TOS_NODE_ID == 1) {
      call CMC0.init(TOS_NODE_ID, server_priv_key, &server_pub_key);
    }
    else {
      call CMC0.init(TOS_NODE_ID, client_priv_key, &client_pub_key);
    }
    
    if (TOS_NODE_ID == 1) {
      call CMC0.bind(1337);
    }
    
    call Timer.startPeriodic(5000);
    
    
    newtime = call LocalTime.get();
    OUT("Socket initialized after %d ms\n", (newtime - oldtime));
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  
  event void Timer.fired() {
    
    // if not server, attempt to connect to server
    if (TOS_NODE_ID != 1 && connected == FALSE && connecting == FALSE) {
      OUT("attempt sync\n");
      oldtime = call LocalTime.get();
      connecting = TRUE;
      if (call CMC0.connect(1337, &server_pub_key) != SUCCESS) {
        OUT("send attempt failed\n");
      }
      //connected = TRUE;
    }
    
    if (TOS_NODE_ID != 1 && connected == TRUE && sending == FALSE) {
      OUT("sending teststring\n");
      if (call CMC0.send(1, teststr, strlen(teststr)) == SUCCESS) {
        sending = TRUE;
      }
    }
  }
  
  
  event void CMC0.connected(error_t e) {
    connecting = FALSE;
    if (e == SUCCESS) {
      newtime = call LocalTime.get();
      OUT("sync was successfull after %d ms\n", (newtime - oldtime));
      connected = TRUE;
    }
    else {
      OUT("connected fail raise\n");
    }
  }
  
  event void CMC0.sendDone(error_t e) {
    sending = FALSE;
  }
  
  event void CMC0.closed(uint16_t remote_id, error_t e){
    
  }
  
  event void CMC0.recv(void* payload, uint16_t plen) {
    // print received messages
    OUT("received string of length %d:\n", plen);
    OUT("%s", payload);
    
    // if server, answer
    if (TOS_NODE_ID == 1) {
      call CMC0.send(1, teststr2, strlen(teststr2));
    }
    
  }
  
  
}
    