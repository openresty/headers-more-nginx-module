#define DDEBUG 0

#include "ddebug.h"

#include "ngx_http_headers_more_input_headers.h"

static ngx_int_t
ngx_http_headers_more_parse_header(ngx_conf_t *cf, ngx_str_t *cmd_name,
        ngx_str_t *raw_header, ngx_array_t *headers,
        ngx_http_headers_more_opcode_t opcode);

static ngx_int_t ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_header_helper(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value,
    ngx_table_elt_t **output_header);

static ngx_int_t ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_content_type_header(ngx_http_request_t *r,
        ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_clear_content_length_header(ngx_http_request_t *r,
        ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);

static ngx_http_headers_more_set_header_t ngx_http_headers_more_set_handlers[] = {

    { ngx_string("Server"),
                 offsetof(ngx_http_headers_out_t, server),
                 ngx_http_set_builtin_header },

    { ngx_string("Date"),
                 offsetof(ngx_http_headers_out_t, date),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Encoding"),
                 offsetof(ngx_http_headers_out_t, content_encoding),
                 ngx_http_set_builtin_header },

    { ngx_string("Location"),
                 offsetof(ngx_http_headers_out_t, location),
                 ngx_http_set_builtin_header },

    { ngx_string("Refresh"),
                 offsetof(ngx_http_headers_out_t, refresh),
                 ngx_http_set_builtin_header },

    { ngx_string("Last-Modified"),
                 offsetof(ngx_http_headers_out_t, last_modified),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Range"),
                 offsetof(ngx_http_headers_out_t, content_range),
                 ngx_http_set_builtin_header },

    { ngx_string("Accept-Ranges"),
                 offsetof(ngx_http_headers_out_t, accept_ranges),
                 ngx_http_set_builtin_header },

    { ngx_string("WWW-Authenticate"),
                 offsetof(ngx_http_headers_out_t, www_authenticate),
                 ngx_http_set_builtin_header },

    { ngx_string("Expires"),
                 offsetof(ngx_http_headers_out_t, expires),
                 ngx_http_set_builtin_header },

    { ngx_string("E-Tag"),
                 offsetof(ngx_http_headers_out_t, etag),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_out_t, content_length),
                 ngx_http_set_content_length_header },

    { ngx_string("Content-Type"),
                 0,
                 ngx_http_set_content_type_header },

    { ngx_null_string, 0, ngx_http_set_header }
};

ngx_int_t
ngx_http_headers_more_exec_input_cmd(ngx_http_request_t *r,
        ngx_http_headers_more_cmd_t *cmd)
{
    ngx_str_t                                   value;
    ngx_http_headers_more_header_val_t          *h;
    ngx_uint_t                                  i;

    if (!cmd->headers) {
        return NGX_OK;
    }

    if (cmd->types) {
        if ( ! ngx_http_headers_more_check_type(r, cmd->types) ) {
            return NGX_OK;
        }
    }

    if (cmd->statuses) {
        if ( ! ngx_http_headers_more_check_status(r, cmd->statuses) ) {
            return NGX_OK;
        }
        dd("status check is passed");
    }

    h = cmd->headers->elts;
    for (i = 0; i < cmd->headers->nelts; i++) {

        if (ngx_http_complex_value(r, &h[i].value, &value) != NGX_OK) {
            return NGX_ERROR;
        }

        if (h[i].handler(r, &h[i], &value) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


