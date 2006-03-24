# -*- coding: ISO8859-1 -*-
#
# Copyright 2003, 2004 Norwegian University of Science and Technology
# Copyright 2006 UNINETT AS
#
# This file is part of Network Administration Visualized (NAV)
#
# NAV is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# NAV is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NAV; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#
# $Id$
# Authors: Morten Vold <morten.vold@itea.ntnu.no>
#          Magnar Sveen <magnars@idi.ntnu.no>
#
"""
This module encompasses modules with web functionality for NAV.
"""
import nav
import time
import ConfigParser
import os.path, nav.path
import cgi

webfrontConfig = ConfigParser.ConfigParser()
webfrontConfig.read(os.path.join(nav.path.sysconfdir, 'webfront', 'webfront.conf'))

def headerparserhandler(req):
    """
    This is a header parser handler for Apache.  It will parse all
    requests to NAV and perform various tasks to exert a certain
    degree of control over the NAV web site.  It makes sure the
    session dictionary is associated with the request object, and
    performs authentication and authorization functions for each
    request.
    """
    import nav.web.auth
    import state
    from mod_python import apache

    # We automagically redirect users to the index page if they
    # request the root.
    if req.uri == '/':
        redirect(req, '/index/index')

    state.setupSession(req)
    nav.web.auth.authenticate(req)

    # Make sure the user's session file has its mtime updated every
    # once in a while, even though no new data is saved to the session
    # (this is so the session won't expire for no apparent reason)
    if (req.session.mtime()+30) < time.time():
        req.session.touch()

    # Make sure the main web template knows which user to produce
    # output for.
    from nav.web.templates.MainTemplate import MainTemplate
    MainTemplate.user = req.session['user']

    return apache.OK


def redirect(req, url, temporary=False, seeOther=False):
    """
    Immediately redirects the request to the given url. If the
    seeOther parameter is set, 303 See Other response is sent, if the
    temporary parameter is set, the server issues a 307 Temporary
    Redirect. Otherwise a 301 Moved Permanently response is issued.
    """
    from mod_python import apache

    if seeOther:
        status = apache.HTTP_SEE_OTHER
    elif temporary:
        status = apache.HTTP_TEMPORARY_REDIRECT
    else:
        status = apache.HTTP_MOVED_PERMANENTLY
    
    req.headers_out['Location'] = url
    req.status = status
    raise apache.SERVER_RETURN, status

def shouldShow(link, user):
    """
    Checks if a link should be shown on the webpage. If the link
    starts with 'http://' or 'https://' it is considered an external
    link and allowed. Internal links are checked using nav.auth.hasPrivilege.
    """
    startsWithHTTP = link.lower()[:7] == 'http://' or link.lower()[:8] == 'https://'
    return startsWithHTTP or nav.auth.hasPrivilege(user, 'web_access', link)

def escape(s):
    """Replace special characters '&', '<' and '>' by SGML entities.
    Wraps cgi.escape, but allows False values of s to be converted to
    empty strings."""
    if s:
        return cgi.escape(str(s))
    else:
        return ''
