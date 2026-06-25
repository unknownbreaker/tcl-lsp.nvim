# -- rweb_content.tcl
#
# content generator root class. Each page or any other content
# generator should subclass this class. 
#
# with this class we inaugurate the term "urlhandler" which
# is meant to replace "datasource"
#

package require Itcl

namespace eval ::rwpage {

    ::itcl::class RWContent {
        private variable key
        private variable hits
        private variable stored_vars
        private variable url_handler
        private variable ctype 

        constructor {pagekey {contenttype "application/octet-stream"}} {
            set key         $pagekey
            set stored_vars [dict create]
            set hits        0
            set ctype       $contenttype
            set url_handler ""
        }

        public method init {args} {}

        protected method postprocessing {urlhandler} {}

        public method set_key {k} { set key $k }
        public method key {} { return $key }
        public method destroy {}
        public method url_args {} { return $stored_vars }
        public method prepare_content { urlhandler language argsqs }
        public method prepare { language argsqs } { return $this }
        public method binary_content { } { return true }
        public method resource_exists {resource_key} { return false }
        public method get_resource_repr {resource_key} { return "" }
        public method print_content {language} { }
        public method current_handler {} { return $url_handler }
        public method mimetype {} { return [$this content_type] }
        public method set_content_type {ct} { set ctype $ct }
        public method content_type {} { return $ctype }
        public method content_disposition {} { return "" }
        public method content_length {} { return "" }
        public method send_headers {} 
        public method send_output {language} { $this print_content $language }
        public method refresh {timereference} { return true }
        public method to_string {} { return [dict create hits $hits key $key] }

        destructor {
            ::rivet::apache_log_error debug "RWContent destructor for $this running"
            ::rwdatas::UrlHandler::notify_handlers page_being_removed [$this key]
        }

    }

# -- send_headers
#
#
    ::itcl::body RWContent::send_headers {} {

        ::rivet::headers type [$this content_type]

        set content_disposition [$this content_disposition] 
        if {$content_disposition != ""} {
            ::rivet::headers add Content-Disposition $content_disposition
        }

        set content_length [$this content_length]
        if {$content_length != ""} {
            ::rivet::headers add Content-Length $content_length
        }

    }

# -- destroy
#
# releases objects which may hold data stored in the pool (e.g. tdom
# objects). Abstract method for this class

    ::itcl::body RWContent::destroy {} {
        ::rivet::apache_log_error debug "RWContent::destroying $this"

#       foreach l [split [::rivetweb::stacktrace] "\n"] {
#           ::rivet::apache:log_error debug $l
#       }

        ::itcl::delete object $this
    }

# -- prepare_content
#
#
# 
    ::itcl::body RWContent::prepare_content {urlhandler language argsqs} {
        set stored_vars $argsqs 
        incr hits

        # this establishes a context relationship between this
        # instance of a web content and a urlhandler (formerly
        # known as Datasource)

        set url_handler $urlhandler

        ::rivet::apache_log_error debug "$this about to call prepare $language"
        set pobject [$this prepare $language $argsqs]
        ::rivet::apache_log_error debug "\[$this prepare $language $argsqs\] returns '$pobject'"

        return $pobject
    }

}
package provide rwcontent 1.0
