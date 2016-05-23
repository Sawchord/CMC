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

#include "CMC.h"

#include "TinyECC/NN.h"
#include "TinyECC/ECC.h"
#include "TinyECC/ECIES.h"

interface CMCClient {
  
  /* intializes the socket, call before use */
  command error_t init(uint16_t local_id, void* buf, uint16_t buf_len, 
    cmc_keypair_t* local_key);
  
  /* connects this socket to the server */
  command error_t connect(uint16_t group_id, Point* remote_public_key);
  
  /* send data over the cannel */
  command error_t send(void* data, uint16_t data_len);
  
  /* closes this connection */
  command error_t close();
  
  /* Signaled after connection established or failed. 
   * Do not send data, before this event was signaled. */
  event void connected(error_t e);
  
  /* Signaled after packet was sent successfully or sent failed.
   * Also indicates, that the cannel is ready to send further data */
  event void sendDone(error_t e);
  
  /* Signals, that the connection has be shut down succesfully.
   * Is also risen with FAIL, if connection is terminated unexpected*/
  event void closed(error_t e);
  
  /* Signaled if data was received*/
  event void recv(void* payload, uint16_t plen);
  
}