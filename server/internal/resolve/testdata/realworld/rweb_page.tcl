# -- rweb_page.tcl
#
# base class for every HTML page
#

package require rwcontent

namespace eval ::rwpage {

    ::itcl::class RWPage {
        inherit RWContent

        private variable metadata
        private variable title
        private variable headline

        constructor {pagekey} {RWContent::constructor $pagekey "text/html"} {
            set metadata    [dict create]
            set title       [dict create]
            set headline    [dict create]
        }

        public method add_metadata {field value}
        public method lappend_metadata {field value}
        public method set_metadata {mdlist}
        public method put_metadata {dictionary}
        public method clear_metadata { } { set metadata [dict create] }
        public method languages { } { return $::rivetweb::default_lang }
        public method metadata {{key ""}}
        public method postproc_hooks { urlhandler hooks_d hooks_class {language ""}} {}
        public method metadata_hooks { hooks_d }
        public method set_title {language title_t} { $this title $language $title_t } ; #DEPRECATED
        private method set_title_dict {language title_txt}
        public method title {{language ""} {txt ""} args}
        public method headline {language {hdl ""}}
        public method to_string {} { return [dict create metadata $metadata {*}[RWContent::to_string]] }
        public method binary_content { } { return false }
        public method content_field {language field {default_val ""}} { return "" }
        public method prepare {language argqs}
        public method prepare_content { urlhandler language argsqs }
        protected method postprocessing { urlhandler }
        public method send_output {language}
        public method content_type {} { return "[RWContent::content_type]; charset=$::rivetweb::http_encoding" }
        public method javascript {} { return "" }
        public method special_headers {language} {}
        protected proc merge_menus {urlhandler_menus}
    }

    ::itcl::body RWPage::merge_menus {urlhandler_menus} {
        dict for {k v} $urlhandler_menus {
            dict lappend ::rivetweb::pagemenus $k {*}$v
        }
    }

    ::itcl::body RWPage::prepare_content {urlhandler language argsqs} {

        # this call to RWContent::prepare_content calls 'prepare' before
        # collecting the menu listing from the Url handlers.
        # 2020/10/26: this fact is badly documented. I guess I placed
        # content generation before picking up menus because the
        # execution may change the application or session status

        set pobject [RWContent::prepare_content $urlhandler $language $argsqs]

        # we rebuild the navigation menu dictionary on every request

        set ::rivetweb::pagemenus [dict create]

        set urlh [::rwdatas::UrlHandler::start_scan]

        while {$urlh != ""} {
            set urlhandler_menus [$urlh menu_list $::rivetweb::current_page]
            ::rivet::apache_log_error debug "got '$urlhandler_menus' from $urlh"
            merge_menus $urlhandler_menus
            set urlh [$urlh next_handler]
        }

        ::rivet::apache_log_error debug "menu database $::rivetweb::pagemenus"

        $pobject postprocessing $urlhandler

        return $pobject
    }

# -- prepare
#
# Collecting menus to be displayed from the registered urlhandlers 
#

    ::itcl::body RWPage::prepare {language argsqs} {

        return [RWContent::prepare $language $argsqs]

    }

# -- postprocessing
#
# Running the page postprocessing hooks (xmlpostproc class)
#
# The method definition still reflects the initial design where
# postproc_hooks handled both xmlpostproc and metadata class 
# hooks. It should change, being the method visibility 'protected' 
#

    ::itcl::body RWPage::postprocessing {urlhandler} {
        RWContent::postprocessing $urlhandler

        if {[catch {

           $this postproc_hooks $urlhandler $::rivetweb::hooks    \
                                xmlpostproc $::rivetweb::language

           $this metadata_hooks $::rivetweb::hooks

        } e einfo]} {

            ::rivet::apache_log_error err "Error in postprocessing page ($e)"
            ::rivet::apache_log_error err $einfo

            set ::rivetweb::current_page [::RWDummy fetch_page postproc_hook_error rkey]

        }

    }

# -- metadata_hooks
#
# metadata hooks are processed in a similar wayto xml postproc hooks, 
# but they apply in slightly different manner
#

    ::itcl::body RWPage::metadata_hooks { hooks_d } {

        if {[dict exists $hooks_d metadata]} {
            set ppp [dict get $hooks_d metadata]
            foreach hk [dict keys $ppp] {

                $::rivetweb::logger log info "processing hook: [dict get $ppp $hk descrip]"
                set processor [dict get $ppp $hk function]
                
                ::rivetweb::$processor $this
            }
        }

    }

# -- set_title_dict
#
# private method to set the title internal dictionary
#

    ::itcl::body RWPage::set_title_dict {language title_txt} {
        dict set title $language $title_txt
        if {![dict exists $title $::rivetweb::default_lang]} {
            dict set title $::rivetweb::default_lang $title_txt
        }
    }

# -- title
#
# A method for getting the page title goes in the base RWPage class
# because <title>...</title> is an element that goes in the <head>...</head>
# section of a page and it's part of the standard HTML ever since
#

    ::itcl::body RWPage::title {{language ""} {titletxt ""} args} { 
        if {$language == ""} {
            return $title
        } else {

            if {[llength $args] == 0} {
                if {$titletxt != ""} {

                    #dict set title $language $titletxt
                    #if {![dict exists $title $::rivetweb::default_lang]} {
                    #    dict set title $::rivetweb::default_lang $titletxt
                    #}

                    $this set_title_dict $language $titletxt

                    return $titletxt

                } elseif {[dict exists $title $language]} {
                    return [dict get $title $language]
                } elseif {[dict exists $title $::rivetweb::default_lang]} {
                    return [dict get $title $::rivetweb::default_lang]
                } else {
                    return ""
                }
            } else {
                foreach {l t} [list $language $titletxt {*}$args] {
                    $this set_title_dict $l $t
                }

                # returning a title anyway

                foreach l [list $language $::rivetweb::default_lang] {
                    if {[dict exists $title $l]} { return [dict get $title $l] }
                }
                return ""
            }

        }
    }

# -- headline
#
# I add a 'headline' method for sake of simplicity, but there is
# no compelling reason to make this a base class method. 

    ::itcl::body RWPage::headline {language {hdl ""}} { 
        if {$hdl != ""} {
            dict set headline $language $hdl      
        } elseif {[dict exists $headline $language]} {
            return [dict get $headline $language]
        } else {
            return [$this title $language]
        }
    }

# -- add_metadata 
#
# method to store in a page instance the metadata associated
# with the keyword 'field' and whose value is 'value'
#
#
    ::itcl::body RWPage::add_metadata {field value} {

        dict set metadata $field $value

    }

# -- lappend_metadata
#
# like add_metadata but list-appending a new value to a
# given fiel
#
#

    ::itcl::body RWPage::lappend_metadata {field value} {

        dict lappend metadata $field $value

    }


# -- set_metadata
#
# the list 'mdlist' is treated as a even length list to be interpreted
# as a sequence of keyword-value pairs. The keywords are assembled and 
# become the new metadata of the instance 'pageobj' erasing metadata 
# that could have been defined beforehand  

    ::itcl::body RWPage::set_metadata {mdlist} {

        set metadata [dict merge $metadata $mdlist]

    }

# -- put_metadata 
# 
# metadata dictionary is replaced by the <dictionary> value
# 

    ::itcl::body RWPage::put_metadata {dictionary} {

        set metadata $dictionary

    }


# -- metadata
#
# when called with no argument 'metadata' returns the whole metadata section,
# when called with a 'key' argument the call returns the metadata value
# corresponding to the 'key'. If the 'key' metadata doesn't exist in the page
# object an empty string is returned.
# 

    ::itcl::body RWPage::metadata {{key ""}} {

        if {$key == ""} {

            return $metadata

        } else {

            if {[dict exists $metadata $key]} {
                return [dict get $metadata $key]
            } else {
                return ""
            }

        }

    }

# -- send_output
#
# this is the method that actually builds the page out of its template.
# In the current design the method accesses variables in the ::rivetweb
# namespace to read the template database and page menu database

    ::itcl::body RWPage::send_output {language} {

        # before we send the output we establish the style template and template rvt scripts
        set template_key $::rivetweb::template_key

        $::rivetweb::logger log debug \
                    "selected template $template_key: [::rivetweb::RWTemplate::template $template_key template]"
        $::rivetweb::logger log debug \
                    "selected css $template_key: [::rivetweb::RWTemplate::template $template_key css]"

        # let's build the full path to the template and css files through the Rivetweb specific calls

        set ::rivetweb::running_template  [::rivetweb::template $template_key]
        set ::rivetweb::running_css       [::rivetweb::csspath  $template_key]

        $::rivetweb::logger log info "running template $::rivetweb::running_template, $::rivetweb::running_css"

        # signaling to any template that needs to redefine resources
        # in case the template has changed

        if {$::rivetweb::template_key != $::rivetweb::last_selected_template} {
            set ::rivetweb::last_selected_template $template_key
            set ::rivetweb::template_changed true
        } else {
            set ::rivetweb::template_changed false
        }

        set class [$this info class]

        ::rivet::apache_log_error debug "parsing $::rivetweb::running_template (${this}: $class)"

        if {$class == "::rwpage::RWBasic"} {
            puts [::rivet::xml [$this pagetext $language] pre]
        }

        #fconfigure stdout -translation lf -encoding $::rivetweb::http_encoding
        ::rivet::parse $::rivetweb::running_template

    }

    proc create {key {class RWStatic}} {
        return [$class ::#auto $key]
    }

    namespace export create
    namespace ensemble create
}

package provide rwpage 2.0

