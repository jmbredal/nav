#!/usr/bin/python
"""
$Id: servicemon.py,v 1.5 2003/06/19 12:50:34 magnun Exp $                                                                                                                              
This file is part of the NAV project.                                                                                             
                                                                                                                                 
Copyright (c) 2002 by NTNU, ITEA nettgruppen                                                                                      
Author: Magnus Nordseth <magnun@stud.ntnu.no>
"""
import os
os.sys.path.append(os.path.split(os.path.realpath(os.sys.argv[0]))[0]+"/lib")
os.sys.path.append(os.path.split(os.path.realpath(os.sys.argv[0]))[0]+"/lib/checker")

import RunQueue, types, time, abstractChecker, getopt, signal, config, db, mailAlert, random
import gc, threading
import debug

class controller:
    def __init__(self, **kwargs):
        signal.signal(signal.SIGHUP, self.signalhandler)
        signal.signal(signal.SIGUSR1, self.signalhandler)
        signal.signal(signal.SIGTERM, self.signalhandler)
        self.conf=config.serviceconf()
        debug.setDebugLevel(self.conf.get('debuglevel',4))
        self._deamon=kwargs.get("fork", 1)
        self._isrunning=1
        self._checkers=[]
        self._pidfile=self.conf.get('pidfile', 'servicemon.pid')
        debug.debug("Wrote pidfile %s" % self._pidfile)
        self._looptime=int(self.conf.get("checkinterval",60))
        debug.debug("Setting checkinterval=%i"% self._looptime)
        self.db=db.db(config.dbconf("db.conf"))
        debug.debug("Reading database config")
        self.db.start()
        debug.debug("Setting up runqueue")
        self._runqueue=RunQueue.RunQueue(controller=self)
        self.alerter=mailAlert.mailAlert()
        self.alerter.start()
        self.dirty = 1


    def createStatusFile(self):
        """
        Dumps the current status to a file.
        """
        try:
            outputfile = open('/var/www/html/services/status.txt','w')
        except:
            debug.debug("Failed to open outputfile: %s" % outputfile,2)
            return

        try:
            for each in self._checkers:
                outputfile.write("%-25s %-5s %-5s %s\n" % (each.getSysname(), each.getType(), each.getStatus(), each.getVersion()) )

            outputfile.write("\n\nLast updated: %s" % time.asctime())
            outputfile.close()
        except:
            debug.debug("Failed to write to %s" % outputfile,2)

                      
    def getCheckers(self):
        """
        Fetches new checkers from the NAV database and appends them to
        the runqueue.
        """
        newcheckers = self.db.getCheckers(self.dirty)
        self.dirty=0

        s=[]    
        for i in newcheckers:
            if i in self._checkers:
                s.append(self._checkers[self._checkers.index(i)])
            else:
                s.append(i)

        self._checkers=s
        #randomiserer rekkef�lgen p� checkerbene
        for i in self._checkers:
            self._checkers.append(self._checkers.pop(int(len(self._checkers)*random.random())))
                    
    def main(self):
        """
        Loops until SIGTERM is caught. The looptime is defined
        by self._looptime
        """

        while self._isrunning:
            start=time.time()
            self.getCheckers()

            wait=self._looptime - (time.time() - start)
            if self._checkers:
                pause=wait/(len(self._checkers)*2)
            else:
                pause=0
            for each in self._checkers:
                self._runqueue.enq(each)
                time.sleep(pause)

            self.createStatusFile()

            # extensive debugging
            #dbgthreads=[]
            #for i in gc.get_objects():
            #    if isinstance(i, threading.Thread):
            #        dbgthreads.append(i)
            #debug.debug("Garbage: %s Objects: %i Threads: %i" % (gc.garbage, len(gc.get_objects()), len(dbgthreads)))

            wait=(self._looptime - (time.time() - start))
            debug.debug("Waiting %i seconds." % wait)
            if wait <= 0:
                debug.debug("Only superman can do this. Humans cannot wait for %i seconds." % wait,2)
                wait %= self._looptime
                time.sleep(wait)
            else:
                time.sleep(wait)


    def signalhandler(self, signum, frame):
        if signum == signal.SIGTERM:
            debug.debug( "Caught SIGTERM. Exiting.")
            self._runqueue.terminate()
            os.sys.exit(0)
        elif signum == signal.SIGUSR1:
            # reopen the logfile
            logfile=self.conf.get("logfile", "servicemon.log")
            debug.debug("Caught SIGUSR1. Reopening logfile...")
            os.sys.stdout.close()
            os.sys.stderr.close()
            os.sys.stdout = open(logfile,'a')
            os.sys.stderr = open(logfile,'a')
            debug.debug("Reopened logfile: %s" % logfile)
        else:
            debug.debug( "Caught %s. Resuming operation." % (signum))


def start(nofork):
    """
    Forks a new prosess, letting the service run as
    a daemon.
    """
    conf = config.serviceconf()
    if fork:
        pid=os.fork()
        if pid > 0:
            pidfile=conf.get('pidfile', 'servicemon.pid')
            try:
                pidfile=open(pidfile, 'w')
                pidfile.write(str(pid)+'\n')
                pidfile.close()
            except Exception, e:
                print "Could not open %s" % pidfile
                print str(e)
            os.sys.exit()
                
        logfile = conf.get('logfile','servicemon.log')
        #print "Logger til ", logfile
        os.sys.stdout = open(logfile,'a')
        os.sys.stderr = open(logfile,'a')

    myController=controller(fork=fork)
    myController.main()
                



def help():
    print """Service monitor for NAV (Network Administration Visualized).

    Usage: %s [OPTIONS]
    -h  --help      Displays this message
    -n  --nofork    Run in foreground
    -v  --version   Display version and exit


Written by Erik Gorset and Magnus Nordseth, 2002

    """  % os.path.basename(os.sys.argv[0])


if __name__=='__main__':
    try:
        opts, args = getopt.getopt(os.sys.argv[1:], 'hnv', ['help','nofork', 'version'])
        fork=1

        for opt, val in opts:
            if opt in ('-h','--help'):
                help()
                os.sys.exit()
            elif opt in ('-n','--nofork'):
                fork=0
            elif opt in ('-v','--version'):
                print __version__
                os.sys.exit(0)
                

    except (getopt.error):
        help()
        os.sys.exit(2)
                               
    start(fork)
