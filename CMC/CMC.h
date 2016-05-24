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
#include "TinyECC/ECC.h"
#include "TinyECC/ECIES.h"

#include "crypto/crypto.h"

/* the cannel for the MCMC network to operate on */
#ifndef AM_CMC
#define AM_CMC 8
#endif


/* the period between two calls to the timer process in milliseconds*/
#ifndef CMC_PROCESS_TIME
#define CMC_PROCESS_TIME 512
#endif

/* the maximum number of clients a server can have */
#ifndef CMC_MAX_CLIENTS
#define CMC_MAX_CLIENTS 16
#endif

/* the length of the callenge and response message */
#ifndef CMC_CALLRES_LENGTH
#define CMC_CALLRES_LENGTH 20
#endif

/* hold a keypair */
typedef struct cmc_keypair_t {
  NN_DIGIT priv;
  Point pub;
} cmc_keypair_t;

/* a single client connections view from the server side */
typedef struct cmc_client_connection_t {
  uint16_t remote_id;
  uint8_t state;
} cmc_client_connection_t;

/* the cmc server socket*/
typedef struct cmc_server_sock_t {
  
  uint8_t sync_state;
  uint8_t msgs_state;
  
  /* the local id is the id, which other nodes refer to this node */
  uint16_t local_id;
  
  /* the group id, which the nodes use to identify this group */
  uint16_t group_id;
  
  /* buffer, for message construction */
  void* buf;
  uint16_t buf_len;
  
  /* this connections private and public key */
  cmc_keypair_t* asym_key;
  
  /* The AES key context, the shared secret between the nodes */
  CipherContext master_key;
  
  // TODO: key whitelist to be compiled into code
  
} cmc_server_sock_t;



/* the cmc client socket*/
typedef struct cmc_client_sock_t {
  
  uint8_t state;
  
  /* ids work the same as in the server */
  uint16_t local_id;
  uint16_t group_id;
  
  
  /* the buffer that is used to construct data before sending */
  void* buf;
  uint16_t buf_len;
  
  
  /* this connections private and public key */
  cmc_keypair_t* key;
  
} cmc_client_sock_t;


/* cmc socket states (for both server and client)*/
typedef enum {
  CMC_CLOSED = 0x0,
  CMC_PRECONNECTION,
  CMC_LISTEN,
  CMC_AUTH,
  CMC_ESTABLISHED,
  CMC_ACKPENDING,
  CMC_PROCESSING,
} cmc_state_e;


/* cmc type flags */
typedef enum {
  CMC_SYNC = 0x0,
  CMC_FINISH,
  CMC_ERR,
  CMC_CHALLENGE,
  CMC_RESPONSE,
  CMC_KEY,
  CMC_ACK,
  CMC_DATA,
} cmc_flag_e;


/* cmc header type */
typedef struct cmc_hdr_t {
  uint16_t src;
  uint16_t dst;
  uint8_t flags;
} cmc_hdr_t;


/* ---------cmc header expansions------------ */

/* sync header */
typedef struct cmc_sync_hdr_t {
  Point public_key;
} cmc_sync_hdr_t;

/* challenge and response header */
typedef struct cmc_callres_hdr_t {
  uint8_t cr[CMC_CALLRES_LENGTH];
} cmc_callres_hdr_t;

/* finish and error header */
typedef struct cmc_ferr_hdr_t {
  uint16_t message;
} cmc_ferr_hdr_t;


typedef struct cmc_key_hdr_t {
  CipherContext context;
} cmc_key_hdr_t;

typedef struct cmc_msg_hdr_t {
  uint16_t length;
} cmc_msg_hdr_t;

#endif /* CMC_H */
