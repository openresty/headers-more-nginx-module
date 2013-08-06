/*
 * Copyright (C) Yichun Zhang (agentzh)
 * */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_headers_more_headers_in.h"
#include "ngx_http_headers_more_util.h"
#include <ctype.h>


static char * ngx_http_headers_more_parse_directive(ngx_conf_t *cf,
    ngx_command_t *ngx_cmd, void *conf,
    ngx_http_headers_more_opcode_t opcode);
static int ngx_http_headers_more_check_type(ngx_http_request_t *r,
    ngx_array_t *types);
static ngx_int_t ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_header_helper(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value,
    ngx_table_elt_t **output_header);
static ngx_int_t ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_user_agent_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_clear_content_length_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_host_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_connection_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);
static ngx_int_t ngx_http_set_cookie_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value);


static ngx_http_headers_more_set_header_t ngx_http_headers_more_set_handlers[]
        = {

#if (NGX_HTTP_GZIP)
    { ngx_string("Accept-Encoding"),
                 offsetof(ngx_http_headers_in_t, accept_encoding),
                 ngx_http_set_builtin_header },

    { ngx_string("Via"),
                 offsetof(ngx_http_headers_in_t, via),
                 ngx_http_set_builtin_header },
#endif

    { ngx_string("Host"),
                 offsetof(ngx_http_headers_in_t, host),
                 ngx_http_set_host_header },

    { ngx_string("Connection"),
                 offsetof(ngx_http_headers_in_t, connection),
                 ngx_http_set_connection_header },

    { ngx_string("If-Modified-Since"),
                 offsetof(ngx_http_headers_in_t, if_modified_since),
                 ngx_http_set_builtin_header },

    { ngx_string("User-Agent"),
                 offsetof(ngx_http_headers_in_t, user_agent),
                 ngx_http_set_user_agent_header },

    { ngx_string("Referer"),
                 offsetof(ngx_http_headers_in_t, referer),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Type"),
                 offsetof(ngx_http_headers_in_t, content_type),
                 ngx_http_set_builtin_header },

    { ngx_string("Range"),
                 offsetof(ngx_http_headers_in_t, range),
                 ngx_http_set_builtin_header },

    { ngx_string("If-Range"),
                 offsetof(ngx_http_headers_in_t, if_range),
                 ngx_http_set_builtin_header },

    { ngx_string("Transfer-Encoding"),
                 offsetof(ngx_http_headers_in_t, transfer_encoding),
                 ngx_http_set_builtin_header },

    { ngx_string("Expect"),
                 offsetof(ngx_http_headers_in_t, expect),
                 ngx_http_set_builtin_header },

    { ngx_string("Authorization"),
                 offsetof(ngx_http_headers_in_t, authorization),
                 ngx_http_set_builtin_header },

    { ngx_string("Keep-Alive"),
                 offsetof(ngx_http_headers_in_t, keep_alive),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_in_t, content_length),
                 ngx_http_set_content_length_header },

    { ngx_string("Cookie"),
                 0,
                 ngx_http_set_cookie_header },

#if (NGX_HTTP_REALIP)
    { ngx_string("X-Real-IP"),
                 offsetof(ngx_http_headers_in_t, x_real_ip),
                 ngx_http_set_builtin_header },
#endif

    { ngx_null_string, 0, ngx_http_set_header }
};


ngx_int_t
ngx_http_headers_more_exec_input_cmd(ngx_http_request_t *r,
    ngx_http_headers_more_cmd_t *cmd)
{
    ngx_str_t                                    value;
    ngx_http_headers_more_header_val_t          *h;
    ngx_uint_t                                   i;

    if (!cmd->headers) {
        return NGX_OK;
    }

    if (cmd->types && !ngx_http_headers_more_check_type(r, cmd->types)) {
        return NGX_OK;
    }

    h = cmd->headers->elts;
    for (i = 0; i < cmd->headers->nelts; i++) {

        if (ngx_http_complex_value(r, &h[i].value, &value) != NGX_OK) {
            return NGX_ERROR;
        }

        if (value.len) {
            value.len--;  /* remove the trailing '\0' added by
                             ngx_http_headers_more_parse_header */
        }

        if (h[i].handler(r, &h[i], &value) != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    return ngx_http_set_header_helper(r, hv, value, NULL);
}


static ngx_int_t
ngx_http_set_header_helper(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value,
    ngx_table_elt_t **output_header)
{
    ngx_table_elt_t             *h;
    ngx_list_part_t             *part;
    ngx_uint_t                   i;
    ngx_uint_t                   rc;

    dd_enter();

    if (r->http_version < NGX_HTTP_VERSION_10) {
        return NGX_OK;
    } 

retry:
    part = &r->headers_in.headers.part;
    h = part->elts;

    for (i = 0; /* void */; i++) {
        dd("i: %d, part: %p", (int) i, part);

        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            h = part->elts;
            i = 0;
        }

        if (h[i].key.len == hv->key.len
            && ngx_strncasecmp(h[i].key.data, hv->key.data,
                               h[i].key.len) == 0)
        {
            if (value->len == 0) {
                h[i].hash = 0;

                rc = ngx_http_headers_more_rm_header_helper(
                                            &r->headers_in.headers, part, i);

                if (rc == NGX_OK) {
                    if (output_header) {
                        *output_header = NULL;
                    }

                    goto retry;
                }
            }

            h[i].value = *value;

            if (output_header) {
                *output_header = &h[i];
                dd("setting existing builtin input header");
            }

            return NGX_OK;
        }
    }

    if (value->len == 0 || hv->replace) {
        return NGX_OK;
    }

    h = ngx_list_push(&r->headers_in.headers);

    if (h == NULL) {
        return NGX_ERROR;
    }

    dd("created new header for %.*s", (int) hv->key.len, hv->key.data);

    if (value->len == 0) {
        h->hash = 0;

    } else {
        h->hash = hv->hash;
    }

    h->key = hv->key;
    h->value = *value;

    h->lowcase_key = ngx_pnalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        return NGX_ERROR;
    }

    ngx_strlow(h->lowcase_key, h->key.data, h->key.len);

    if (output_header) {
        *output_header = h;

        while (r != r->main) {
            r->parent->headers_in = r->headers_in;
            r = r->parent;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    ngx_table_elt_t             *h, **old;

    dd("entered set_builtin_header (input)");

    if (hv->offset) {
        old = (ngx_table_elt_t **) ((char *) &r->headers_in + hv->offset);

    } else {
        old = NULL;
    }

    dd("old builtin ptr ptr: %p", old);
    if (old) {
        dd("old builtin ptr: %p", *old);
    }

    if (old == NULL || *old == NULL) {
        dd("set normal header");
        return ngx_http_set_header_helper(r, hv, value, old);
    }

    h = *old;

    if (value->len == 0) {
        h->hash = 0;
        h->value = *value;

        return ngx_http_set_header_helper(r, hv, value, old);
    }

    h->hash = hv->hash;
    h->value = *value;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_host_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    dd("server new value len: %d", (int) value->len);

    r->headers_in.server = *value;

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    off_t           len;

    if (value->len == 0) {
        return ngx_http_clear_content_length_header(r, hv, value);
    }

    len = ngx_atosz(value->data, value->len);
    if (len == NGX_ERROR) {
        return NGX_ERROR;
    }

    dd("reset headers_in.content_length_n to %d", (int)len);

    r->headers_in.content_length_n = len;

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_content_length_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    r->headers_in.content_length_n = -1;

    return ngx_http_clear_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    value->len = 0;
    return ngx_http_set_builtin_header(r, hv, value);
}


char *
ngx_http_headers_more_set_input_headers(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    return ngx_http_headers_more_parse_directive(cf, cmd, conf,
                                         ngx_http_headers_more_opcode_set);
}


char *
ngx_http_headers_more_clear_input_headers(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf)
{
    return ngx_http_headers_more_parse_directive(cf, cmd, conf,
                                        ngx_http_headers_more_opcode_clear);
}


static int
ngx_http_headers_more_check_type(ngx_http_request_t *r, ngx_array_t *types)
{
    ngx_uint_t          i;
    ngx_str_t           *t;
    ngx_str_t           actual_type;

    if (r->headers_in.content_type == NULL) {
        return 0;
    }

    actual_type = r->headers_in.content_type->value;
    if (actual_type.len == 0) {
        return 0;
    }

    dd("headers_in->content_type: %.*s",
       (int) actual_type.len,
       actual_type.data);

    t = types->elts;
    for (i = 0; i < types->nelts; i++) {
        dd("...comparing with type [%.*s]", (int) t[i].len, t[i].data);

        if (actual_type.len == t[i].len
            && ngx_strncmp(actual_type.data, t[i].data, t[i].len) == 0)
        {
            return 1;
        }
    }

    return 0;
}


static char *
ngx_http_headers_more_parse_directive(ngx_conf_t *cf, ngx_command_t *ngx_cmd,
    void *conf, ngx_http_headers_more_opcode_t opcode)
{
    ngx_http_headers_more_loc_conf_t   *hcf = conf;

    ngx_uint_t                          i;
    ngx_http_headers_more_cmd_t         *cmd;
    ngx_str_t                           *arg;
    ngx_flag_t                          ignore_next_arg;
    ngx_str_t                           *cmd_name;
    ngx_int_t                           rc;
    ngx_flag_t                          replace = 0;
    ngx_http_headers_more_header_val_t  *h;

    if (hcf->cmds == NULL) {
        hcf->cmds = ngx_array_create(cf->pool, 1,
                                     sizeof(ngx_http_headers_more_cmd_t));

        if (hcf->cmds == NULL) {
            return NGX_CONF_ERROR;
        }
    }

    cmd = ngx_array_push(hcf->cmds);

    if (cmd == NULL) {
        return NGX_CONF_ERROR;
    }

    cmd->headers = ngx_array_create(cf->pool, 1,
                                sizeof(ngx_http_headers_more_header_val_t));

    if (cmd->headers == NULL) {
        return NGX_CONF_ERROR;
    }

    cmd->types = ngx_array_create(cf->pool, 1, sizeof(ngx_str_t));
    if (cmd->types == NULL) {
        return NGX_CONF_ERROR;
    }

    cmd->statuses = NULL;

    arg = cf->args->elts;

    cmd_name = &arg[0];

    ignore_next_arg = 0;

    for (i = 1; i < cf->args->nelts; i++) {
        if (ignore_next_arg) {
            ignore_next_arg = 0;
            continue;
        }

        if (arg[i].len == 0) {
            continue;
        }

        if (arg[i].data[0] != '-') {
            rc = ngx_http_headers_more_parse_header(cf, cmd_name,
                                                    &arg[i], cmd->headers,
                                                    opcode,
                                        ngx_http_headers_more_set_handlers);

            if (rc != NGX_OK) {
                return NGX_CONF_ERROR;
            }

            continue;
        }

        if (arg[i].len == 2) {
            if (arg[i].data[1] == 't') {
                if (i == cf->args->nelts - 1) {
                    ngx_log_error(NGX_LOG_ERR, cf->log, 0,
                                  "%V: option -t takes an argument.",
                                  cmd_name);

                    return NGX_CONF_ERROR;
                }

                rc = ngx_http_headers_more_parse_types(cf->log, cmd_name,
                                                       &arg[i + 1],
                                                       cmd->types);

                if (rc != NGX_OK) {
                    return NGX_CONF_ERROR;
                }

                ignore_next_arg = 1;

                continue;

            } else if (arg[i].data[1] == 'r') {
              dd("Found replace flag");
              replace = 1;
              continue;
            }
        }

        ngx_log_error(NGX_LOG_ERR, cf->log, 0,
                      "%V: invalid option name: \"%V\"", cmd_name, &arg[i]);

        return NGX_CONF_ERROR;
    }

    dd("Found %d types, and %d headers",
       (int) cmd->types->nelts,
       (int) cmd->headers->nelts);

    if (cmd->headers->nelts == 0) {
        ngx_pfree(cf->pool, cmd->headers);
        cmd->headers = NULL;

    } else {
        h = cmd->headers->elts;
        for (i = 0; i < cmd->headers->nelts; i++) {
            h[i].replace = replace;
        }
    }

    if (cmd->types->nelts == 0) {
        ngx_pfree(cf->pool, cmd->types);
        cmd->types = NULL;
    }

    cmd->is_input = 1;

    ngx_http_headers_more_handler_used = 1;

    return NGX_CONF_OK;
}


/* borrowed the code from ngx_http_request.c:ngx_http_process_user_agent */
static ngx_int_t
ngx_http_set_user_agent_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    u_char  *user_agent, *msie;

    /* clear existing settings */

    r->headers_in.msie = 0;
    r->headers_in.msie6 = 0;
    r->headers_in.opera = 0;
    r->headers_in.gecko = 0;
    r->headers_in.chrome = 0;
    r->headers_in.safari = 0;
    r->headers_in.konqueror = 0;

    if (value->len == 0) {
        return ngx_http_set_builtin_header(r, hv, value);
    }

    /* check some widespread browsers */

    user_agent = value->data;

    msie = ngx_strstrn(user_agent, "MSIE ", 5 - 1);

    if (msie && msie + 7 < user_agent + value->len) {

        r->headers_in.msie = 1;

        if (msie[6] == '.') {

            switch (msie[5]) {
            case '4':
            case '5':
                r->headers_in.msie6 = 1;
                break;
            case '6':
                if (ngx_strstrn(msie + 8, "SV1", 3 - 1) == NULL) {
                    r->headers_in.msie6 = 1;
                }
                break;
            }
        }
    }

    if (ngx_strstrn(user_agent, "Opera", 5 - 1)) {
        r->headers_in.opera = 1;
        r->headers_in.msie = 0;
        r->headers_in.msie6 = 0;
    }

    if (!r->headers_in.msie && !r->headers_in.opera) {

        if (ngx_strstrn(user_agent, "Gecko/", 6 - 1)) {
            r->headers_in.gecko = 1;

        } else if (ngx_strstrn(user_agent, "Chrome/", 7 - 1)) {
            r->headers_in.chrome = 1;

        } else if (ngx_strstrn(user_agent, "Safari/", 7 - 1)
                   && ngx_strstrn(user_agent, "Mac OS X", 8 - 1))
        {
            r->headers_in.safari = 1;

        } else if (ngx_strstrn(user_agent, "Konqueror", 9 - 1)) {
            r->headers_in.konqueror = 1;
        }
    }

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_set_connection_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    r->headers_in.connection_type = 0;

    if (value->len == 0) {
        return ngx_http_set_builtin_header(r, hv, value);
    }

    if (ngx_strcasestrn(value->data, "close", 5 - 1)) {
        r->headers_in.connection_type = NGX_HTTP_CONNECTION_CLOSE;
        r->headers_in.keep_alive_n = -1;

    } else if (ngx_strcasestrn(value->data, "keep-alive", 10 - 1)) {
        r->headers_in.connection_type = NGX_HTTP_CONNECTION_KEEP_ALIVE;
    }

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_set_cookie_header(ngx_http_request_t *r,
    ngx_http_headers_more_header_val_t *hv, ngx_str_t *value)
{
    ngx_table_elt_t  **cookie, *h;

    if (r->headers_in.cookies.nelts > 0) {
        ngx_array_destroy(&r->headers_in.cookies);

        if (ngx_array_init(&r->headers_in.cookies, r->pool, 2,
                           sizeof(ngx_table_elt_t *))
            != NGX_OK)
        {
            return NGX_ERROR;
        }

        dd("clear headers in cookies: %d", (int) r->headers_in.cookies.nelts);
    }

#if 1
    if (r->headers_in.cookies.nalloc == 0) {
        if (ngx_array_init(&r->headers_in.cookies, r->pool, 2,
                           sizeof(ngx_table_elt_t *))
            != NGX_OK)
        {
            return NGX_ERROR;
        }
    }
#endif

    h = NULL;
    if (ngx_http_set_header_helper(r, hv, value, &h) == NGX_ERROR) {
        return NGX_ERROR;
    }

    if (value->len == 0) {
        return NGX_OK;
    }

    dd("new cookie header: %p", h);

    cookie = ngx_array_push(&r->headers_in.cookies);
    if (cookie == NULL) {
        return NGX_ERROR;
    }

    *cookie = h;
    return NGX_OK;
}
