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
configuration CMCBenchC {
  
} implementation {
  
  components MainC, LedsC;
  components CMCBenchP;
  
  CMCBenchP.Boot -> MainC;
  CMCBenchP.Leds -> LedsC;
  
  components new TimerMilliC() as Timer;
  CMCBenchP.Timer -> Timer;
  
  components LocalTimeMicroC;
  CMCBenchP.LocalTime -> LocalTimeMicroC;
  
  components ActiveMessageC;
  CMCBenchP.RadioControl -> ActiveMessageC;
  
  components new CMCSocket() as CMC0;
  CMCBenchP.CMC0 -> CMC0;
  
 
  components SerialStartC;
  components PrintfC;
  
  // ECC components
  components ECCC,NNM, ECIESC;
  CMCBenchP.NN -> NNM;
  CMCBenchP.ECC -> ECCC;
  
  components RandomC;
  CMCBenchP.Random -> RandomC;
  
  components SHA1M;
  CMCBenchP.SHA1 -> SHA1M.SHA1;
}