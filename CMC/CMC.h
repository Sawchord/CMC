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

#ifndef CMC_H
#define CMC_H


// for Point and NN_WORDS
#include "TinyECC/NN.h"



/* the period between two calls to the timer process in milliseconds*/
#ifndef CMC_PROCESS_TIME
#define CMC_PROCESS_TIME 512
#endif

/* the maximum number of clients a server can have */
#ifndef CMC_MAX_CLIENTS
#define CMC_MAX_CLIENTS 16
#endif



/* a single client connections view from the server side */
typdef struct cmc_client_connection_t {
  uint16_t remote_id;
  uint8_t state;
} cmc_client_connection_t;

/* the cmc server socket*/
typedef struct cmc_server_sock_t {
  
  uint16_t state;
  
  /* the group id, which the nodes use to identify this group */
  uint16_t group_id;
  
  /* this connections private and publich key */
  NN_DIGIT* private_key[NUM_WORDS];
  Point* public_key;
  
  
  /* the server needs to keep some information about every connected client independently */
  cmc_client_connection_t[CMC_MAX_CLIENTS] connection;
  
  // TODO: allowed key whitelist to be compiled into code
  
} cmc_server_sock_t;

/* the cmc client socket*/
typedef struct cmc_client_sock_t {
  
  uint16_t state;
  uint16_t group_id;
  
  /* this connections private and public key */
  NN_DIGIT* private_key[NUM_WORDS];
  Point* public_key;
  
  
} cmc_client_sock_t;



/* cmc server socket states */
typedef enum {
  CMC_SERV_CLOSED = 0x0,
  CMC_SERV_LISTEN,
  CMC_SERV_AUTH,
  CMC_SERV_AUTH,
  CMC_SERV_ESTABLISHED,
  CMC_SERV_ACKPENDING,
  CMC_SERV_PROCESSING,
} cmc_server_state_e;


/* cmc client socket states */
typedef enum {
  CMC_CLI_CLOSED = 0x0,
  CMC_CLI_PRECONNECTION,
  CMC_CLI_AUTH,
  CMC_CLI_ESTABLISHED,
  CMC_CLI_PROCESSING,
  CMC_CLI_ACKPENDING,
} cmc_client_states_e;


/* cmc type flags */
typedef enum {
  CMC_SYNC = 0x1,
  CMC_FINISH = 0x2,
  CMC_ERR = 0x4,
  CMC_CHALLENGE = 0x8,
  CMC_RESPONSE = 0x10,
  CMC_KEY = 0x20,
  CMC_ACK = 0x40,
  CMC_DATA = 0x80,
} cmc_flag_e;


/* cmc header type */
typedef struct cmc_hdr_t {
  uint16_t src;
  uint16_t dst;
  uint8_t type;
} cmc_hdr_t;



/* ---------cmc header expansions------------ */

/* sync header */
typdef struct cmc_sync_hdr_t {
  uint16_t group_id;
  Point* public_key;
} cmc_sync_hdr_t;



#endif
