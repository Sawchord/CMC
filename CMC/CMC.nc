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

interface CMC {
  
  /* intializes the socket, call before use */
  command error_t init(uint16_t local_id, NN_DIGIT* private_key);
  
  /* opens this socket for connections */
  command error_t bind(uint16_t group_id);
  
  /* connects this socket to the server */
  command error_t connect(uint16_t group_id);
  command error_t connect_add_data(uint16_t group_id, uint8_t* add_data, uint8_t add_data_length);
  
  /* send data over the cannel */
  command error_t send(uint16_t dest_id, void* data, uint8_t data_len);
  
  /* used to fork a complete socket */
  command uint8_t get_sock_ref();
  command error_t fork_sock(uint8_t sock_ref);
  
  /* let socket change its role */
  command error_t make_server();
  command error_t make_client(uint16_t nodeid);
  
  /* reset a socket into its initial state */
  command error_t reset();
  
  /* The user can implement its own logic, whether to accept a connection */
  event bool accept(uint16_t node_id, Point* remote_public_key, uint8_t* add_data, uint8_t add_data_len);
  
  /* Signaled, whenever a node has connected or failed to connect this server */
  event void connected(error_t e, uint16_t nodeid);
  
  /* Signaled after packet was sent successfully or sent failed.
   * Also indicates, that the cannel is ready to send further data */
  event void sendDone(error_t e);
  
  /* Signals, that the connection has be shut down succesfully.
   * Is also risen with FAIL, if connection is terminated unexpected*/
  //event void closed(uint16_t remote_id, error_t e);
  
  /* Signaled if data was received*/
  event void recv(void* payload, uint16_t plen, uint16_t nodeid);
  
}