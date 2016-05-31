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


configuration CMCC {
  provides interface CMC[uint8_t client];
} implementation {
  
  components MainC;
  components new TimerMilliC();
  components RandomC;
  
  components CMCP;
  
  MainC -> CMCP.Init;
  CMCP.Boot -> MainC;
  
  CMCP.Timer -> TimerMilliC;
  CMCP.Random -> RandomC;
  
  /* radio components */
  components ActiveMessageC;
  
  components new AMSenderC(AM_CMC);
  components new AMReceiverC(AM_CMC);


  CMCP.Packet -> AMSenderC;
  CMCP.AMSend -> AMSenderC;
  CMCP.Receive -> AMReceiverC;
  
  
  CMC = CMCP;
  
  // ECC components
  components ECCC,NNM, ECIESC;
  CMCP.NN -> NNM;
  CMCP.ECC -> ECCC;
  CMCP.ECIES -> ECIESC;
  
  components CTRModeM;
  //components AES128M;
  components XTEAM;
  
  CMCP.BlockCipher -> XTEAM;
  //CMCP.BlockCipherInfo -> AES128M;
  
}