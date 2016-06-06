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
configuration CMCExC {
  
} implementation {
  
  components MainC, LedsC;
  components CMCExP;
  
  CMCExP.Boot -> MainC;
  CMCExP.Leds -> LedsC;
  
  components new TimerMilliC() as Timer;
  CMCExP.Timer -> Timer;
  
  components LocalTimeMilliC;
  CMCExP.LocalTime -> LocalTimeMilliC;
  
  components ActiveMessageC;
  CMCExP.RadioControl -> ActiveMessageC;
  
  components new CMCSocket() as CMC0;
  CMCExP.CMC0 -> CMC0;
  
 
  components SerialStartC;
  components PrintfC;
  
  // ECC components
  components ECCC,NNM, ECIESC;
  CMCExP.NN -> NNM;
  CMCExP.ECC -> ECCC;
  CMCExP.ECIES -> ECIESC;
  
  
  components SHA1M;
  CMCExP.SHA1 -> SHA1M.SHA1;
}