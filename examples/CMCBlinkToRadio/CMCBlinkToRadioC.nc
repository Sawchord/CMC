#include <Timer.h>
#include "CMCBlinkToRadio.h"

module CMCBlinkToRadioC {
    uses interface Boot;
    uses interface Leds;
    uses interface Timer<TMilli> as Timer0;
    
    uses interface SplitControl as RadioControl;
    uses interface CMC as CMC0;

}

implementation {
  uint16_t counter = 0;
  bool busy = FALSE;
        
  event void Boot.booted() {
    counter++;
    call Leds.set(counter);
    call RadioControl.start();
  }
    
  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      if (TOS_NODE_ID == 1) {
        call CMC0.bind(123);
        counter++;
        call Leds.set(counter);
      }
      else {
        call CMC0.connect(123);
      }
    }
    else {
      call RadioControl.start();
    }
  }
    
  event void RadioControl.stopDone(error_t err) {
  }

  event void Timer0.fired() {
    BlinkToRadioMsg btrpkt;
    counter++;
    
    btrpkt.nodeid = TOS_NODE_ID;
    btrpkt.counter = counter;
    
    //if (!busy) {
      if (call CMC0.send(0xff, &btrpkt, sizeof(BlinkToRadioMsg)) == SUCCESS) {
          //busy = TRUE;
      }
    //}
  }
    
  event void CMC0.connected(error_t e, uint16_t nodeid) {
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
    //if (len == sizeof(BlinkToRadioMsg)) {
        BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)payload;
        
        call Leds.set(btrpkt->counter);
    //}
    
    return;
  }
}

