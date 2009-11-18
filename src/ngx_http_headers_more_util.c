#define DDEBUG 0

#include "ddebug.h"

#include "ngx_http_headers_more_util.h"
#include <ctype.h>

ngx_int_t
ngx_http_headers_more_parse_header(ngx_conf_t *cf, ngx_str_t *cmd_name,
        ngx_str_t *raw_header, ngx_array_t *headers,
        ngx_http_headers_more_opcode_t opcode,
        ngx_http_headers_more_set_header_t *handlers)
{
    ngx_http_headers_more_header_val_t             *hv;

    ngx_uint_t                        i;
    ngx_str_t                         key = ngx_string("");
    ngx_str_t                         value = ngx_string("");
    ngx_flag_t                        seen_end_of_key;
    ngx_http_compile_complex_value_t  ccv;

    hv = ngx_array_push(headers);
    if (hv == NULL) {
        return NGX_ERROR;
    }

    seen_end_of_key = 0;
    for (i = 0; i < raw_header->len; i++) {
        if (key.len == 0) {
            if (isspace(raw_header->data[i])) {
                continue;
            }

            key.data = raw_header->data;
            key.len  = 1;

            continue;
        }

        if (!seen_end_of_key) {
            if (raw_header->data[i] == ':'
                    || isspace(raw_header->data[i])) {
                seen_end_of_key = 1;
                continue;
            }

            key.len++;

            continue;
        }

        if (value.len == 0) {
            if (raw_header->data[i] == ':'
                    || isspace(raw_header->data[i])) {
                continue;
            }

            value.data = &raw_header->data[i];
            value.len  = 1;

            continue;
        }

        value.len++;
    }

    if (key.len == 0) {
        ngx_log_error(NGX_LOG_ERR, cf->log, 0,
              "%V: no key found in the header argument: %V",
              cmd_name, raw_header);

        return NGX_ERROR;
    }

    hv->hash = 1;
    hv->key = key;
    hv->offset = 0;

    for (i = 0; handlers[i].name.len; i++) {
        if (hv->key.len != handlers[i].name.len
                || ngx_strncasecmp(hv->key.data, handlers[i].name.data,
                    handlers[i].name.len) != 0)
        {
            dd("hv key comparison: %s <> %s", handlers[i].name.data, hv->key.data);

            continue;
        }

        hv->offset = handlers[i].offset;
        hv->handler = handlers[i].handler;

        break;
    }

    if (handlers[i].name.len == 0 && handlers[i].handler) {
        hv->offset = handlers[i].offset;
        hv->handler = handlers[i].handler;
    }

    if (opcode == ngx_http_headers_more_opcode_clear) {
        value.len = 0;
    }

    if (value.len == 0) {
        ngx_memzero(&hv->value, sizeof(ngx_http_complex_value_t));
        return NGX_OK;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    ccv.cf = cf;
    ccv.value = &value;
    ccv.complex_value = &hv->value;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}

