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

 
module OCBTestP {
  uses {
  
  interface Boot;
  interface Leds;
  
  interface OCBMode;
  }
} implementation {
 
 
  void print_dbg(uint8_t* data, uint16_t length) {
  #ifndef TOSSIM 
    return:
  #else
    uint16_t i;
    for (i = 0; i < length; i++) {
      dbg("App", "%02x ", data[i]);
    }
    return;
  #endif
  }
  
 
 //char message[] = "This is a realy secret message\n";
  
  uint8_t message1[] = {65,66,67,68,69,70,71,72, 0};
  
  
  event void Boot.booted() {
    
    // prepare the field
    
    uint8_t space1[sizeof(clear_t)];
    uint8_t space2[sizeof(hdr_t) + sizeof(enc_t)];
    
    CipherModeContext my_context;
    
    // the initialization key for OCBMode
    uint8_t key[] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
    
    clear_t* clear_data = (clear_t*) space1;
    hdr_t* header = (hdr_t*) space2;    
    enc_t* enc_data = (enc_t*) ((void*)space2 + sizeof(hdr_t));
    
    error_t err;
    
    
    dbg("App", "Booted\n");
    //dbg("App", "BSIZE %d\n", BSIZE);
    
    
    // fill in the data
    header->src_id = 1;
    header->group_id = 1337;
    header->dst_id = 2;
    header->type = 3;
    
    memcpy(&clear_data->data, message1, 9);
    clear_data->length = 9;
    
    dbg("App", "This is the message to send: %s\n", &clear_data->data);
    
    
    err = call OCBMode.init(&my_context, 16, &key);
    dbg("App", "Err: %d\n", err);
    
    
    call OCBMode.set_counter(&my_context, (uint64_t) *key);
    dbg("App", "Err: %d\n", err);
    
    dbg("App", "My context: %x\n", my_context.context);
    
    call OCBMode.encrypt(&my_context, clear_data, header, enc_data,
    9, 5, 30, NULL);
    dbg("App", "Err: %d\n", err);
    
    
    
    return;
  }
  
}





