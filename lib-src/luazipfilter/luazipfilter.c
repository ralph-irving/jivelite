
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zlib.h"

#include "lua.h"
#include "lauxlib.h"


typedef unsigned int u32_t;
typedef unsigned short u16_t;


/* Define LUAZIP_API for dll exports on windows */
#ifndef LUAZIP_API
#define LUAZIP_API
#endif

#define DEBUG(fmt, ...) //fprintf(stderr, "%s:%d " fmt, __FILE__, __LINE__, ##__VA_ARGS__);

#define READ_U16(ptr) (ptr[0] | (ptr[1] << 8)), ptr+=2
#define READ_U32(ptr) (ptr[0] | (ptr[1] << 8) | (ptr[2] << 16) | (ptr[3] << 24)), ptr+=4


/* parser state */
enum zip_state {
	PARSE_FILE_HEADER,
	PARSE_FILENAME,
	COPY_DATA,
	COPY_DEFLATE_INIT,
	COPY_DEFLATE,
	COPY_END,
	PARSE_DATA_DESCRIPTION,
	PARSE_CENTRAL_DIRECTORY,
	ERROR,
};

struct zip_info {
	enum zip_state state;

	/* file header */
	u16_t version;
	u16_t flag;
	u16_t method;
	u16_t mod_time;
	u16_t mod_date;
	u32_t crc;
	u32_t compressed_size;
	u32_t uncompressed_size;
	u16_t filename_length;
	u16_t extra_field_length;

	/* read data */
	u32_t compressed_len;
	struct z_stream_s strm;
	unsigned char *output_buffer;
};

#define OUTPUT_BUFFER_SIZE 4096



static int zip_filter_func(lua_State *L) {
	struct zip_info *zip_info;
	const unsigned char *ptr, *end;
	size_t src_len;
	u32_t signature, len;
	int err;

	/* internal state */
	zip_info = lua_touserdata(L, lua_upvalueindex(1));

	/* combine with any remaining buffer from previous call */
	if (!lua_isnil(L, lua_upvalueindex(2))) {
		DEBUG("MERGING REMAINEDER\n");

		lua_pushvalue(L, lua_upvalueindex(2));

		if (lua_isnil(L, 1)) {
			/* end of file */
			lua_remove(L, 1);
		}
		else {
			/* combine strings */
			lua_insert(L, 1);
			lua_concat(L, 2);
		}

		lua_pushnil(L);
		lua_replace(L, lua_upvalueindex(2));
	}

	/* input buffer */
	ptr = (const unsigned char *)lua_tolstring(L, 1, &src_len);
	end = ptr + src_len;

	while (1) {
		len = end - ptr;

		switch (zip_info->state) {

		case PARSE_FILE_HEADER:
			DEBUG("PARSE FILE HEADER\n");

			if (lua_isnil(L, 1)) {
				/* empty file */
				lua_pushnil(L);
				return 1;
			}

			if (end - ptr < 30 /* local file header length */) {
				lua_pushlstring(L, (const char *)ptr, end - ptr);
				lua_replace(L, lua_upvalueindex(2));

				lua_pushstring(L, "");
				return 1;
			}

			signature = READ_U32(ptr);
			switch (signature) {
			case 0x04034b50:
				// file header, let's continue
				break;
			case 0x02014b50:
				zip_info->state = PARSE_CENTRAL_DIRECTORY;
				continue;
			default:
				zip_info->state = ERROR;
				continue;
			}

			zip_info->version = READ_U16(ptr);
			zip_info->flag = READ_U16(ptr);
			zip_info->method = READ_U16(ptr);
			zip_info->mod_time = READ_U16(ptr);
			zip_info->mod_date = READ_U16(ptr);
			zip_info->crc = READ_U32(ptr);
			zip_info->compressed_size = READ_U32(ptr);
			zip_info->uncompressed_size = READ_U32(ptr);
			zip_info->filename_length = READ_U16(ptr);
			zip_info->extra_field_length = READ_U16(ptr);

			zip_info->compressed_len = 0;
			zip_info->state = PARSE_FILENAME;
			break;
			
		case PARSE_FILENAME:
			DEBUG("PARSE FILENAME\n");

			if (end - ptr < zip_info->filename_length + zip_info->extra_field_length) {
				lua_pushlstring(L, (const char *)ptr, end - ptr);
				lua_replace(L, lua_upvalueindex(2));

				lua_pushstring(L, "");
				return 1;
			}

			/* Return zip file info in a table */
			lua_newtable(L);

			lua_pushinteger(L, zip_info->compressed_size);
			lua_setfield(L, -2, "compressed_size");

			lua_pushinteger(L, zip_info->uncompressed_size);
			lua_setfield(L, -2, "uncompressed_size");

			lua_pushlstring(L, (const char *)ptr, zip_info->filename_length);
			lua_setfield(L, -2, "filename");

			ptr += zip_info->filename_length;

			/* Nothing of interest (yet) in the extra field */
			ptr += zip_info->extra_field_length;

			switch (zip_info->method) {
			case 0:
				zip_info->state = COPY_DATA;
				break;

			case 8:
				zip_info->state = COPY_DEFLATE_INIT;
				break;

			default:
				// unsupported method
				zip_info->state = ERROR;
				return luaL_error(L, "Unsupport method %d\n", zip_info->method);
			}

			if (end - ptr > 0) {
				lua_pushlstring(L, (const char *)ptr, end - ptr);
				lua_replace(L, lua_upvalueindex(2));
			}
			return 1;
			
		case COPY_DATA:
			DEBUG("COPY DATA %d %d\n", zip_info->compressed_len + len, zip_info->compressed_size);

			/* copy the data to output */
			if (len > zip_info->compressed_size - zip_info->compressed_len) {
				len = zip_info->compressed_size - zip_info->compressed_len;
			}

			zip_info->compressed_len += len;

			if (zip_info->compressed_size == zip_info->compressed_len) {
				zip_info->state = COPY_END;
			}

			lua_pushlstring(L, (const char *)ptr, len);
			ptr += len;

			/* store any remainder */
			if (end - ptr > 0) {
				lua_pushlstring(L, (const char *)ptr, end - ptr);
				lua_replace(L, lua_upvalueindex(2));
			}
			return 1;

		case COPY_DEFLATE_INIT:
			DEBUG("COPY_DEFLATE_INIT\n");

			if (inflateInit2(&zip_info->strm, -MAX_WBITS) != Z_OK) {
				zip_info->state = ERROR;
				return luaL_error(L, "inflateInit2 error: %s\n", zip_info->strm.msg);
			}

			zip_info->output_buffer = malloc(OUTPUT_BUFFER_SIZE);

			zip_info->state = COPY_DEFLATE;

			break;

		case COPY_DEFLATE:
			DEBUG("COPY_DEFLATE\n");

			if (len == 0) {
				/* need more input data */
				if (lua_isnil(L, 1)) {
					lua_pushvalue(L, 1);
				}
				else {
					lua_pushstring(L, "");
				}
				return 1;
			}

			zip_info->strm.next_in = (Bytef *)ptr;
			zip_info->strm.avail_in = len;

			zip_info->strm.next_out = zip_info->output_buffer;
			zip_info->strm.avail_out = OUTPUT_BUFFER_SIZE;

			err = inflate(&zip_info->strm, Z_NO_FLUSH);

			ptr = zip_info->strm.next_in;
			len = zip_info->strm.avail_in;

			/* copy inflated data to lua string */
			lua_pushlstring(L, (const char *)zip_info->output_buffer, OUTPUT_BUFFER_SIZE - zip_info->strm.avail_out);

			switch (err) {
			case Z_STREAM_END:
				inflateEnd(&zip_info->strm);
				free(zip_info->output_buffer);

				zip_info->state = COPY_END;
				break;

			case Z_OK:
				// ok, continue
				break;

			default:
				inflateEnd(&zip_info->strm);
				free(zip_info->output_buffer);

				zip_info->state = ERROR;
				return luaL_error(L, "inflate error: %s\n", zip_info->strm.msg);
			}

			/* store any remainder */
			if (end - ptr > 0) {
				lua_pushlstring(L, (const char *)ptr, end - ptr);
				lua_replace(L, lua_upvalueindex(2));
			}

			return 1;

		case COPY_END:
			zip_info->state = (zip_info->flag & 1<<3) ? PARSE_DATA_DESCRIPTION : PARSE_FILE_HEADER;
			break;

		case PARSE_DATA_DESCRIPTION:
			DEBUG("PARSE_DATA_DESCRIPTION\n");

			signature = READ_U32(ptr);
			if (signature != 0x08074b50) {
				// signature is optional!
				ptr -= 4;
			}

			zip_info->crc = READ_U32(ptr);
			zip_info->compressed_size = READ_U32(ptr);
			zip_info->uncompressed_size = READ_U32(ptr);

			zip_info->state = PARSE_FILE_HEADER;
			break;

		case PARSE_CENTRAL_DIRECTORY:
			DEBUG("PARSE_CENTRAL_DIRECTORY\n");

			/* We are at the end of the zip file, either return the empty string or nil */
			if (lua_isnil(L, 1)) {
				lua_pushnil(L);
			}
			else {
				lua_pushstring(L, "");
			}
			return 1;

		case ERROR:
			DEBUG("ERROR\n");

			/* We are at the end of the zip file, either return the empty string or nil */
			if (lua_isnil(L, 1)) {
				lua_pushnil(L);
			}
			else {
				lua_pushstring(L, "");
			}
			return 1;
		}
	}

	return 1;
}


static int zip_filter(lua_State *L) {
	struct zip_info *zip_info;

	zip_info = lua_newuserdata(L, sizeof(struct zip_info));
	memset(zip_info, 0, sizeof(struct zip_info));
	zip_info->state = PARSE_FILE_HEADER;

	lua_pushnil(L); /* remaining buffer */
	lua_pushcclosure(L, zip_filter_func, 2);

	return 1;
}


static const struct luaL_Reg ziplib[] = {
	{ "filter", zip_filter },
	{ NULL, NULL }
};


LUAZIP_API int luaopen_zipfilter(lua_State *L) {
	luaL_register(L, "zip", ziplib);
	return 1;
}

