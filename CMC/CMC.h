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

// a public key in octet form is 42 byte in size for ECC160R1
#define CMC_POINT_SIZE 42
// the cipher context of a xtea is 16 bytes
#define CMC_CC_SIZE 16

/* the cannel for the MCMC network to operate on */
#ifndef AM_CMC
#define AM_CMC 8
#endif


/* the period between two calls to the timer process in milliseconds*/
#ifndef CMC_PROCESS_TIME
#define CMC_PROCESS_TIME 500
#endif

/* the number of retries, before the sockets gives up */
#ifndef CMC_N_RETRIES
#define CMC_N_RETRIES 3
#endif

/* the tim ebetween two retries*/
#ifndef CMC_RETRY_TIME
#define CMC_RETRY_TIME 2000
#endif

/* the maximum number of clients a server can have */
#ifndef CMC_MAX_CLIENTS
#define CMC_MAX_CLIENTS 16
#endif

/* the maximum length of a Packet in IEEE 802.15 in bytes*/
#ifndef CMC_MAX_MSG_LENGTH
#define CMC_MAX_MSG_LENGTH 114
#endif

/* debug output definnition*/
#ifdef DEBUG_OUT
#include <printf.h>
#define DBG(...) printf(__VA_ARGS__); printfflush()
#else
#define DBG(...) 
#endif

/* the cmc server socket*/
typedef struct cmc_sock_t {
  
  uint8_t sync_state;
  uint8_t com_state;
  
  /* the local id is the id, which other nodes refer to this node */
  uint16_t local_id;
  
  /* the group id, which the nodes use to identify this group */
  uint16_t group_id;
  
  /* the id of the server must be know by every node */
  uint16_t server_id;
  
  /* buffer, for message construction */
  uint8_t last_msg[CMC_MAX_MSG_LENGTH];
  
  // TODO: need hash buffer or something?
  
  /* this connections private and public key */
  NN_DIGIT* private_key;
  Point* public_key;
  
  /* the clients need to know the servers public key */
  Point* server_public_key;
  
  /* The AES key context, the shared secret between the nodes */
  CipherContext master_key;
  
  // TODO: key whitelist to be compiled into code
  
} cmc_sock_t;



/* cmc socket states (for both server and client)*/
enum {
  CMC_CLOSED = 0x0,
  CMC_PRECONNECTION,
  CMC_LISTEN,
  CMC_ESTABLISHED,
  CMC_ACKPENDING1,
  CMC_ACKPENDING2,
};


/* cmc type flags */
typedef enum {
  CMC_SYNC = 0x0,
  CMC_ERR,
  CMC_KEY,
  CMC_ACK,
  CMC_DATA,
};


/* cmc header type */
typedef struct cmc_hdr_t {
  uint16_t src_id;
  uint16_t group_id;
  uint16_t dst_id;
  uint8_t type;
} cmc_hdr_t;


/* ---------cmc header expansions------------ */

/* sync header */
typedef struct cmc_sync_hdr_t {
  uint8_t public_key[CMC_POINT_SIZE];
} cmc_sync_hdr_t;

/* and error header */
typedef struct cmc_err_hdr_t {
  uint16_t message;
} cmc_ferr_hdr_t;


typedef struct cmc_key_hdr_t {
  // and ECIES encrypted message is 61 byte longer than its cleantext
  uint8_t encrypted_context[61 + CMC_CC_SIZE];
} cmc_key_hdr_t;

typedef struct cmc_data_hdr_t {
  uint16_t length;
} cmc_msg_hdr_t;

// TODO: Ack header

#endif /* CMC_H */
