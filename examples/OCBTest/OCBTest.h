
#ifndef OCB_TEST_H
#define OCB_TEST_H

/* The cmc header type */
typedef nx_struct hdr_t {
  nx_uint16_t src_id;
  nx_uint16_t group_id;
  nx_uint16_t dst_id;
  nx_uint8_t type;
} hdr_t;


#define DATAFIELD_SIZE 80

/* header that holds the clear data */
typedef nx_struct clear_t {
  nx_uint8_t length;
  nx_uint8_t data[DATAFIELD_SIZE];
} clear_t;


typedef nx_struct enc_t {
  nx_uint8_t key[8];
  nx_uint8_t cipher[DATAFIELD_SIZE + 16];
} enc_t;
  


#endif /* OCB_TEST_H */