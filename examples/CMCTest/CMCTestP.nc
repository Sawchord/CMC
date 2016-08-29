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
    //interface LocalTime<TMilli>;
    
    interface Random;
    
    interface NN;
    interface ECC;
    interface ECIES;
    
    interface SHA1;
    
    
  }
} implementation {
  
  // Control flow aid
  bool sending = FALSE;
  bool connected = FALSE;
  bool connecting = FALSE;
  
  NN_DIGIT private_key[NUMWORDS];
  Point public_key;
  
  // generated with openssl
  uint8_t key0[] = "49:f1:47:8a:cd:ea:73:13:91:f3:b3:4f:19:de:4d:9d:fe:2d:21:0e";
  uint8_t key1[] = "3c:c7:c9:d8:37:82:c7:7a:c6:89:b8:29:11:80:a2:47:18:e6:bf:4f";
  uint8_t key2[] = "53:f0:88:87:95:69:17:60:31:5f:a4:d4:63:23:bc:1e:f3:e9:31:3a";
  
  uint8_t* keylist[] = {key0, key1, key2};
  
  LedMsg answer;
  
  event void Boot.booted() {
    
    // Start the radio interface
    call RadioControl.start();
    
  }
  
  /*
   * Reads the openssl hex representation of an ECC
   * key into an actual NN_DIGIT representation.
   * Since this function is usefull for the whole package,
   * it should be moved into some util package or something 
   * in the future.
   */
  void hex_to_key(NN_DIGIT* out, uint8_t* in) {
    
    uint8_t i;
    
    for (i = 0; i < NUMWORDS-1; i++) {
      uint8_t first_digit, second_digit;
      
      first_digit = in[3*i];
      second_digit = in[3*i + 1];
      
      // parse the first digit
      if (first_digit >= 0x30 && first_digit <= 0x39)
        out[i] = ((first_digit - 0x30) << 4);
      else if (first_digit >= 0x61 && first_digit <= 0x66)
        out[i] = ((first_digit - 0x61 + 0xA) << 4);
      else {
        //OUT("Error while parsing first_digit hex to NN_DIGIT\n");
        return;
      }
      
      
      // parse the first digit
      if (second_digit >= 0x30 && second_digit <= 0x39)
        out[i] |= (second_digit - 0x30);
      else if (second_digit >= 0x61 && second_digit <= 0x66)
        out[i] |= (second_digit - 0x61 + 0xA);
      else {
        //OUT("Error while parsing second_digit hex to NN_DIGIT\n");
        return;
      }
      
    }
    return;
  }
  
  
  event void RadioControl.startDone(error_t e) {
    
    
    if (e != SUCCESS) {
      OUT("error starting radio retry\n");
      call RadioControl.start();
      return;
    }
    
    OUT("Radio up\n");
    
    hex_to_key(private_key, keylist[TOS_NODE_ID-1]);
    OUT("This node has the private key:");
    print_hex(private_key, NUMWORDS);
    
    call ECC.gen_public_key(&public_key, private_key);
    
    // Initialze the CMC interface
    call CMC0.init(TOS_NODE_ID, private_key, &public_key);
    
    // Node 1 becomes the server with group id 1234
    if (TOS_NODE_ID == 1) {
      call CMC0.bind(1234);
    }
    
    // Node 3 is the bitmask generator
    if (TOS_NODE_ID != 1) {
      call Timer.startPeriodic(2000);
    }
    
  }
  
  event void RadioControl.stopDone(error_t e) {}
  
  event void CMC0.connected(error_t e, uint16_t nodeid) {
    
    connecting = FALSE;
    
    if (e == SUCCESS) {
      OUT("Server has synced successfull with %d\n", nodeid);
      connected = TRUE;
    }
    else {
      OUT("sync failed\n");
    }
  }
  
  event void CMC0.sendDone(error_t e) {
    
    if (e != SUCCESS) {
      OUT("Sending has failed, need to reconnect\n");
      connected = FALSE;
      call Timer.startPeriodic(2000);
      return;
    }
    
    OUT("Send done signaled\n");
    sending = FALSE;
  }
  
  
  event void CMC0.recv(void* payload, uint16_t plen, uint16_t nodeid) {
    
    LedMsg* data;
    
    //if (plen != sizeof(LedMsg)) {
    //  OUT("Recv msg, but len was not matching\n");
    //  return;
    //}
    
    data = (LedMsg*) payload;
    
    // The server needs to resend the stuff
    if (TOS_NODE_ID == 1 && data->dst_id != 1) {
      
      if (data->dst_id > 3) {
        OUT("No fitting node in scope\n");
        return;
      }
      
      
      if (call CMC0.send(data->dst_id, data, sizeof(LedMsg) != SUCCESS)) {
         OUT("Server error while resending the data\n");
      }
      else {
        OUT("Resent bitmask %d from %d for %d\n", data->bitmask, data->nodeid, data->dst_id);
      }
      
      return;
    }
    
    OUT("recvd bitmask %d from node %d for %d\n", data->bitmask, data->nodeid, data->dst_id);
    
    if (data->dst_id == TOS_NODE_ID) {
      OUT("Thats me\n");
      call Leds.set(data->bitmask);
    }
    
    return;
  }
  
  event void Timer.fired() {
    
    LedMsg msg;
    uint8_t tbit;
    
    if (connected == FALSE && connecting == FALSE) {
      if (call CMC0.connect(1234) != SUCCESS) {
        OUT("Error while connecting");
      }
      connecting = TRUE;
      return;  
    }
    
    // If node is currently connecting, need to wait.
    if (connecting == TRUE) return;
    
    // If still in sending, sending not needed.
    if (sending == TRUE) return;
    
    // Only node 2 needs to keeps the timer fireing
    if (TOS_NODE_ID != 2) {
      call Timer.stop();
      return;
    }
    
    tbit = call Random.rand16();
    
    msg.nodeid = TOS_NODE_ID;
    msg.dst_id = 0x02 & tbit;
    
    tbit = call Random.rand16();
    
    msg.bitmask = 0x04 & tbit;
    
    OUT("Sending bitmask %d to node %d\n", msg.bitmask, msg.dst_id);
    
    if(call CMC0.send(0, &msg, sizeof(LedMsg)) != SUCCESS) {
      OUT("Error while sending LedMsg\n");
    }
    
    sending = TRUE;
    return;
    
  }
  
}
    
