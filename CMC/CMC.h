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

// xtea works in 8 byte blocks
#define CMC_CC_BLOCKSIZE 8


/* the hashsize of the hash used in cmc, currently sha1 */
#define CMC_HASHSIZE 20

#define CMC_DATAFIELD_SIZE TOSH_DATA_LENGTH-CMC_HASHSIZE-sizeof(nx_uint16_t)

/* the cannel for the MCMC network to operate on */
#ifndef AM_CMC
#define AM_CMC 8
#endif


/* the period between two calls to the timer process in milliseconds*/
#ifndef CMC_PROCESS_TIME
#define CMC_PROCESS_TIME 2000
#endif

/* the number of retries, before the sockets gives up */
#ifndef CMC_N_RETRIES
#define CMC_N_RETRIES 3
#endif

/* the tim ebetween two retries*/
#ifndef CMC_RETRY_TIME
#define CMC_RETRY_TIME 8000
#endif

/* the maximum number of clients a server can have */
#ifndef CMC_MAX_CLIENTS
#define CMC_MAX_CLIENTS 16
#endif

/* the maximum length of a Packet in IEEE 802.15 in bytes*/
#ifndef CMC_MAX_MSG_LENGTH
#define CMC_MAX_MSG_LENGTH 114
#endif

#define GET_SP *((uint16_t*) 0x1e)

/* debug output definition*/
#ifdef DEBUG_OUT
  #ifdef TOSSIM
    //#include <printf.h>
    #define DBG(...) dbg("CMC", __VA_ARGS__);
  #else
    #include <printf.h>
    //#define DBG(...) printf("(%04x): ", GET_SP); printf(__VA_ARGS__); printfflush()
    #define DBG(...) printf(__VA_ARGS__); printfflush()
  #endif
#else
  #define DBG(...) 
#endif

uint16_t get_sp() {
  uint16_t* sp = (uint16_t*) 0x1e;
  return *sp;
}

/* the cmc server socket*/
typedef struct cmc_sock_t {
  
  uint8_t sync_state;
  uint8_t com_state;
  
  /* the local id is the id, which other nodes refer to this node */
  uint16_t local_id;
  
  /* the group id, which the nodes use to identify this group */
  uint16_t group_id;
  
  /* buffer, for message construction */
  uint8_t last_dst;
  uint8_t last_msg[CMC_DATAFIELD_SIZE];
  uint8_t last_msg_len;
  
  
  /* this connections private and public key */
  NN_DIGIT* private_key;
  Point* public_key;
  
  /* The AES key context, the shared secret between the nodes */
  CipherContext master_key;
  
  uint8_t retry_counter;
  uint16_t retry_timer;
  
} cmc_sock_t;

/* 
 * This is a debug function,
 * that needs to be removed at the end.
 */
void print_hex (void* data, uint16_t length) {
  int i = 0;
  
  for (i = 0; i < length; i++) {
    if (i % 8 == 0) DBG("\n");
    
    DBG("0x%02x ", ((uint8_t*)data)[i]);
  }
  DBG("\n");
}

/* cmc socket states (for both server and client)*/
enum {
  CMC_CLOSED = 0x0,
  CMC_PRECONNECTION,
  CMC_LISTEN,
  CMC_ESTABLISHED,
  CMC_ACKPENDING,
};


/* cmc type flags */
enum {
  CMC_SYNC = 0x0,
  CMC_KEY,
  CMC_DATA,
};



/* The cmc header type */
typedef nx_struct cmc_hdr_t {
  nx_uint16_t src_id;
  nx_uint16_t group_id;
  nx_uint16_t dst_id;
  nx_uint8_t type;
} cmc_hdr_t;


/* ---------cmc header expansions------------ */

/* sync header */
typedef nx_struct cmc_sync_hdr_t {
  nx_uint8_t public_key[CMC_POINT_SIZE];
} cmc_sync_hdr_t;


typedef nx_struct cmc_key_hdr_t {
  // and ECIES encrypted message is 61 byte longer than its cleantext
  nx_uint8_t encrypted_context[61 + CMC_CC_SIZE];
} cmc_key_hdr_t;


typedef nx_struct cmc_clear_data_hdr_t {
  nx_uint16_t group_id;
  nx_uint8_t hash[CMC_HASHSIZE];
  
  // this MUST come last
  nx_uint8_t data[CMC_DATAFIELD_SIZE];
} cmc_clear_data_hdr_t;


typedef nx_struct cmc_data_hdr_t {
  nx_uint16_t length;
  nx_union {
    cmc_clear_data_hdr_t clear_data;
    nx_uint8_t enc_data[sizeof (cmc_clear_data_hdr_t)];
  };
} cmc_data_hdr_t;

#endif /* CMC_H */
