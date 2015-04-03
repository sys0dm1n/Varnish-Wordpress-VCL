# default backend definition.  Set this to point to your content server.
backend default {
    .host = "YourBackendIPhere";
    .port = "80";
    .connect_timeout = 120s;
    .first_byte_timeout = 120s;
    .between_bytes_timeout = 120s;
}

### Called when a client request is received

sub vcl_recv {

# shortcut for DFind requests
  if (req.url ~ "^/w00tw00t") {
        error 404 "Not Found";
  }

# Dont cache the RSS feed
  if (req.url ~ "/feed") {
    return (pass);
  }
# Compatibility with Apache format log
  if (req.restarts == 0) {
    if (req.http.x-forwarded-for) {
      set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    } else {
        set req.http.X-Forwarded-For = client.ip;
      }
  }

  if (req.request != "GET" &&
    req.request != "HEAD" &&
    req.request != "PUT" &&
    req.request != "POST" &&
    req.request != "TRACE" &&
    req.request != "OPTIONS" &&
    req.request != "DELETE" &&
    req.request != "PURGE") {
      /* Non-RFC2616 or CONNECT which is weird. */
      return (pipe);
    }

  if (req.http.Accept-Encoding) {
#revisit this list
    if (req.url ~ "\.(gif|jpg|jpeg|swf|flv|mp3|mp4|pdf|ico|png|gz|tgz|bz2)(\?.*|)$") {
      remove req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
      set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate") {
      set req.http.Accept-Encoding = "deflate";
    } else {
      remove req.http.Accept-Encoding;
    }
  }

# Strip out Google Analytics campaign variables. They are only needed
# by the javascript running on the page
# utm_source, utm_medium, utm_campaign, gclid
  if(req.url ~ "(\?|&)(gclid|utm_[a-z]+)=") {
    set req.url = regsuball(req.url, "(gclid|utm_[a-z]+)=[-_A-z0-9]+&?", "");
    set req.url = regsub(req.url, "(\?|&)$", "");
  }


# remove double // in urls,
set req.url = regsuball( req.url, "//", "/" );
#// remove extra http:// calls at the end of the url
  if (req.url ~ "^/\?http://") {
    set req.url = regsub(req.url, "\?http://.*", "");
  }

# Don't cache sitemap.xml
  if(req.url ~ "/sitemap.xml"){
    return (pass);
  }

  if (req.url ~ "^/[^?]+\.(jpeg|jpg|png|gif|ico|js|css|txt|gz|zip|lzma|bz2|tgz|tbz|html|htm|swf|flv|mp3|mp4|pdf)(\?.*|)$") {
    unset req.http.cookie;
    set req.url = regsub(req.url, "\?.*$", "");
  }
  if (req.url ~ "\?(utm_(campaign|medium|source|term)|adParams|client|cx|eid|fbid|feed|ref(id|src)?|v(er|iew))=") {
    set req.url = regsub(req.url, "\?.*$", "");
  }
  if (req.http.cookie ~ "(wordpress_|wp-settings-|NO_CACHE=)") {
      return(pass);
    } else {
      unset req.http.cookie;
      return (lookup);
    }
}

### Called when the requested object has been retrieved from the backend, or the request to the backend has failed

sub vcl_fetch {
  # Remove User-Agent before caching
  if (beresp.http.Vary ~ "User-Agent") {
    set beresp.http.Vary = regsub(beresp.http.Vary, ",? User-Agent ", "");
    set beresp.http.Vary = regsub(beresp.http.Vary, "^, *", "");
    if (beresp.http.Vary == "") {
        unset beresp.http.Vary;
    }
  }

  if (req.request == "POST" || req.url ~ "wp-(login|admin)" || req.url ~ "preview=true" || req.url ~ "xmlrpc.php") {
    return (hit_for_pass);
 # uncomment for debug   
 #   set beresp.http.X-Cacheable = "NO:Not Cacheable";
  }
  if ( req.request == "GET" || (!(req.url ~ "(wp-(login|admin)|login)")) || (req.request != "POST") ) {
    unset beresp.http.set-cookie;
# uncomment for debug
#    set beresp.http.X-Cacheable = "SEY";
  }

  if (req.url ~ "\.(jpeg|jpg|png|gif|ico|js|css|txt|gz|zip|lzma|bz2|tgz|tbz|html|htm|swf|flv|mp3|mp4|pdf)(\?.*|)$"){
    set beresp.ttl = 365d;
# uncomment for debug
#    set beresp.http.X-Cacheable = "YES";
  }

  if (beresp.http.Content-Type ~ "text/html" || beresp.http.Content-Type ~ "text/xml" || beresp.http.Content-Type ~ "text/htm"){
    set beresp.ttl = 4h;
# uncomment for debug
#    set beresp.http.X-Cacheable = "YES";
  }

 # Keep all objects for 6h longer in the cache than their TTL specifies.
 # So even if HTTP objects are expired (they've passed their TTL), we can still use them in case all backends go down.
 # Remember: old content to show is better than no content at all (or an error page).
  set beresp.grace = 6h;

#  return (deliver);
}

sub vcl_deliver {
# multi-server webfarm? set a variable here so you can check
# the headers to see which frontend served the request
#   set resp.http.X-Server = "server-01";
   if (obj.hits > 0) {
     set resp.http.X-Cache = "HIT";
     set resp.http.X-Cache-Hits = obj.hits;
   } else {
     set resp.http.X-Cache = "MISS";
   }

   # Remove some headers: PHP version
   unset resp.http.X-Powered-By;

   # Remove some headers: Apache version & OS
   unset resp.http.Server;

   # Remove some heanders: Varnish
   unset resp.http.Via;
   unset resp.http.X-Varnish;

   return (deliver);
}
