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
  
  // Variables used for benchmar
  uint32_t oldtime, newtime;
  
  // Control flow aid
  bool sending = FALSE;
  bool connected = FALSE;
  bool connecting = FALSE;
  
  
  //SensorMsg send_msg;
  //SensorMsg* recv_msg;
  
  
  // Holds private and public keys
  NN_DIGIT private_key[NUMWORDS];
  Point public_key;
  
  // generated with openssl
  uint8_t key0[] = "49:f1:47:8a:cd:ea:73:13:91:f3:b3:4f:19:de:4d:9d:fe:2d:21:0e";
  uint8_t key1[] = "3c:c7:c9:d8:37:82:c7:7a:c6:89:b8:29:11:80:a2:47:18:e6:bf:4f";
  uint8_t key2[] = "53:f0:88:87:95:69:17:60:31:5f:a4:d4:63:23:bc:1e:f3:e9:31:3a";
  
  uint8_t* keylist[] = {key0, key1, key2};
  
  // Last reads from the sensors
  uint8_t last_lum_read;
  uint16_t last_temp_read;
  
  
  event void Boot.booted() {
    oldtime = call LocalTime.get();
    
    // Start the radio interface
    call RadioControl.start();
    
  }
  
  /*
   * Reads the openssl hex representation of an ECC
   * key into an actual NN_DIGIT representation.
   */
  void hex_to_key(NN_DIGIT* out, uint8_t* in) {
    
    uint8_t i;
    
    OUT("NN_DIGIT: %d\n", sizeof(NN_DIGIT));
    
    for (i = 0; i < NUMWORDS; i++) {
      uint8_t first_digit, second_digit;
      
      first_digit = in[3*i];
      second_digit = in[3*i + 1];
      
      // parse the first digit
      if (first_digit >= 0x30 && first_digit <= 0x39)
        out[i] = (first_digit - 0x30) << 4;
      else if (first_digit >= 0x61 && first_digit <= 0x66)
        out[i] = (first_digit - 0x61) << 4;
      else {
        OUT("Error while parsing first_digit hex to NN_DIGIT");
        return;
      }
      
      
      // parse the first digit
      if (second_digit >= 0x30 && second_digit <= 0x39)
        out[i] = (second_digit - 0x30);
      else if (second_digit >= 0x61 && second_digit <= 0x66)
        out[i] = (second_digit - 0x61);
      else {
        OUT("Error while parsing second_digit hex to NN_DIGIT");
        return;
      }
      
      
      
    }
    return;
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
      // This is the server printing the data
      if (plen != sizeof(SensorMsg)) {
        OUT("Recvs msgs, with non fitting length");
        return;
      }
      else {
        SensorMsg* data;
        
        data = (SensorMsg*) payload;
        
        OUT("Status of node:%d: Temp:%d, Lum:%d\n", data->nodeid, data->temp, data->lum);
        return;
      }
      return;
    }
    else if (TOS_NODE_ID == 2) {
      
      if (plen != sizeof(LedMsg)) {
        OUT("Recvs msgs, but len was not matching\n");
      }
      else {
        // This is, where node 2 assembles the answer for the led bitmask
        
        LedMsg answer;
        LedMsg* data;
        
        uint8_t tbit;
        
        data = (LedMsg*) payload;
        
        tbit = call Random.rand16();
        
        OUT("Sending bitmask: %d to node %d\n", tbit, data->nodeid);
        
        answer.nodeid = TOS_NODE_ID;
        answer.bitmask = tbit;
        
        call CMC0.send(data->nodeid, &answer, sizeof(answer));
        sending = TRUE;
        return;
      }
      
    }
    else {
      
      // This is where all other nodes receive their bitmask
      if (plen != sizeof(LedMsg)) {
        OUT("Recvds weirds message\n");
        return;
      }
      else {
        
        LedMsg* data;
        
        data = (LedMsg*) payload;
        if (data->nodeid == 2) {
          call Leds.set(data->bitmask);
        }
        return;
      }
    }
    return;
  }
  
  event void Timer.fired() {
    
    if (connected == FALSE && connecting == FALSE) {
      if (call CMC0.connect(1234, &public_key) != SUCCESS) {
        OUT("Error while connecting");
      }
      connecting = TRUE;
      return;  
    }
    
    // If node is currently coneecting, need to wait.
    if (connecting = TRUE) return;
    
    // If still in sending, sending not needed.
    if (sending == TRUE) return;
    
    if (call Random.rand16() >> 15) {
      LedMsg msg;
      
      msg.nodeid = TOS_NODE_ID;
      msg.bitmask = 0x0;
      
      if(call CMC0.send(2, &msg, sizeof(msg)) != SUCCESS) {
        OUT("Error while sending LedMsg\n");
      }
      
      sending = TRUE;
      return;
    }
    
    // Start the sensor reading process
    if (call LightRead.read() != SUCCESS) {
      OUT("Error while calling Light read\n");
    }
    return;
  }
  
  
  event void LightRead.readDone(error_t err, uint8_t lum) {
    
    if (err != SUCCESS) {
      OUT("Error in Light read done\n");
    }
    else {
      last_lum_read = lum;
      if (call TempRead.read() != SUCCESS) {
        OUT("Error while calling Temp read\n");
      }
    }
    return;
    
  }
  
  event void TempRead.readDone(error_t err, uint16_t temp) {
    
    if (err != SUCCESS) {
      OUT("Error in Temp read done\n");
    }
    else {
      SensorMsg msg;
      last_temp_read = temp;
      
      msg.nodeid = TOS_NODE_ID;
      msg.temp = last_temp_read;
      msg.lum = last_lum_read;
      
      if(call CMC0.send(1, &msg, sizeof(msg)) != SUCCESS) {
        OUT("Error while sending\n");
      }
      sending = TRUE;
    }
    
  }
  
}
    