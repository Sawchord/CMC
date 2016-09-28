#include <Timer.h>
#include <NN.h>
#include <ECC.h>
#include <ECIES.h>

#include <printf.h>
#include <CMC.h>

#include "CMCBlinkToRadio.h"

module CMCBlinkToRadioC {
    uses interface Boot;
    uses interface Leds;
    uses interface Timer<TMilli> as Timer0;
    
    uses interface SplitControl as RadioControl;
    uses interface CMC as CMC0;
    
    // The interfaces include functionality needed to operate CMC
    uses interface NN;
    uses interface ECC;
    uses interface ECIES;
    
    
}

implementation {
  
  uint8_t key0[] = "49:f1:47:8a:cd:ea:73:13:91:f3:b3:4f:19:de:4d:9d:fe:2d:21:0e";
  uint8_t key1[] = "3c:c7:c9:d8:37:82:c7:7a:c6:89:b8:29:11:80:a2:47:18:e6:bf:4f";
  uint8_t key2[] = "53:f0:88:87:95:69:17:60:31:5f:a4:d4:63:23:bc:1e:f3:e9:31:3a";
  
  uint8_t* keylist[] = {key0, key1, key2};
  
  NN_DIGIT private_key[NUMWORDS];
  Point public_key;
  
  uint16_t counter = 0;
  bool busy = FALSE;
  
  // this ugly function should be hidden away from public eyey, but there was no place to fit it in.
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
  
  event void Boot.booted() {
    counter++;
    call Leds.set(counter);
    call RadioControl.start();
  }
    
  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      
      // load the key into its field
      hex_to_key(private_key, keylist[TOS_NODE_ID-1]);
      
      // generate public key
      call ECC.gen_public_key(&public_key, private_key);
      
      // initialize the CMC module
      call CMC0.init(TOS_NODE_ID, private_key, &public_key);
      
      // node 1 is server, the others are clients
      if (TOS_NODE_ID == 1) {
        call CMC0.bind(123);
        counter++;
        call Leds.set(counter);
      }
      else {
        call CMC0.connect(123);
      }
    }
    // retry radio, if it did not start
    else {
      call RadioControl.start();
    }
  }
    
  event void RadioControl.stopDone(error_t err) {
  }

  event void Timer0.fired() {
    BlinkToRadioMsg btrpkt;
    counter++;
    
    // fill packet with information
    btrpkt.nodeid = TOS_NODE_ID;
    btrpkt.counter = counter;
    
    if (!busy) {
      if (call CMC0.send(0xffff, &btrpkt, sizeof(BlinkToRadioMsg)) == SUCCESS) {
          busy = TRUE;
      }
    }
  }
    
  event void CMC0.connected(error_t e, uint16_t nodeid) {
    // nodes increase counter, whenever the get new connections
    if (TOS_NODE_ID == 1) {
      counter++;
      call Leds.set(counter);
    }
    else {
      counter++;
      call Leds.set(counter);
      call Timer0.startPeriodic(2000);
    }
  }
  
  event void CMC0.sendDone(error_t error) {
    busy = FALSE;
  }

  event void CMC0.recv(void* payload, uint16_t len, uint16_t nodeid) {
    if (len == sizeof(BlinkToRadioMsg)) {
        BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)payload;
        
        call Leds.set(btrpkt->counter);
    }
    
    return;
  }
}

