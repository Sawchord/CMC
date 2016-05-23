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
 

#include <tinypkc/ecc.h>
#include <tinypkc/integer.h>

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
    interface SlitControl as RadioControl;
    
    interface CMCServer as Server0;
    
    interface Leds;
    
    interface Timer<TMilli>;
    interace LocalTime<TMilli>;
    
    interface Random;
    
    interface ECC;
  }
} implementation {
  
  uint32_t oldtime, newtime;
  
  uint8_t buffer[1024];
  
  bool connected = FALSE;
  bool connecting = FALSE;
  bool sending = FALSE;
  
  mp_digit  local_key_buff[4* MP_PREC];
  ecc_key   local_key;
  mp_digit  remote_key_buf[4* MP_PREC];
  ecc_key   remote_key;
  
  
  event void Boot.booted() {
    oldtime = call LocalTime.get();
    // start the radio
    call RadioControl.start();
    
  }
  
  event void 
}
    