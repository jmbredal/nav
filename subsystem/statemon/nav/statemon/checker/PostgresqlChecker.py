# -*- coding: utf-8 -*-
#
# Copyright (C) 2003,2004 Norwegian University of Science and Technology
#
# This file is part of Network Administration Visualized (NAV).
#
# NAV is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License version 2 as published by the Free
# Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.  You should have received a copy of the GNU General Public
# License along with NAV. If not, see <http://www.gnu.org/licenses/>.
#

from nav.statemon.abstractChecker import AbstractChecker
from nav.statemon import Socket
from nav.statemon.event import Event


class PostgresqlChecker(AbstractChecker):
    def __init__(self, service, **kwargs):
        AbstractChecker.__init__(self,'postgresql', service,  port=5432, **kwargs)
    def execute(self):
        args = self.getArgs()
        s = Socket.Socket(self.getTimeout())
        s.connect(self.getAddress())
        s.close()
        return Event.UP,'alive'

def getRequiredArgs():
    """
    Returns a list of required arguments
    """
    requiredArgs = []
    return requiredArgs

