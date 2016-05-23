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


configuration CMCServerC {
  provides interface CMCServer[uint8_t server];
} implementation {
  
  components MainC;
  components new TimerMilliC();
  components RandomC;
  
  components CMCServerP;
  
  MainC -> CMCServerP.Init;
  CMCServerP.Boot -> MainC;
  
  CMCServerP.Timer -> TimerMilliC;
  CMCServerP.Random -> RandomC;
  
  /* radio components */
  components new AMSenderC(AM_CMC);
  components new AMReceiverC(AM_CMC);


  CMCServerP.Packet -> AMSenderC;
  CMCServerP.AMSend -> AMSenderC;
  CMCServerP.Receive -> AMReceiverC;
  
  
  CMCServer = CMCServerP;
  
  // ECC components
  components ECCC,NNM, ECIESC;
  CMCServerP.NN -> NNM;
  CMCServerP.ECC -> ECCC;
  CMCServerP.ECIES -> ECIESC;
  
}