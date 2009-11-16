#ifndef NGX_HTTP_HEADERS_MORE_FILTER_MODULE_H
#define NGX_HTTP_HEADERS_MORE_FILTER_MODULE_H

#include <ngx_core.h>
#include <ngx_http.h>

typedef struct {
    ngx_array_t                       *types; /* of ngx_str_t */
    ngx_array_t                       *statuses; /* of ngx_uint_t */
    ngx_array_t                       *headers; /* of ngx_http_header_val_t */
} ngx_http_headers_more_cmd_t;

typedef struct {
    ngx_array_t             *cmds; /* of ngx_http_headers_more_cmd_t */
} ngx_http_headers_more_conf_t;

#endif /* NGX_HTTP_HEADERS_MORE_FILTER_MODULE_H */

