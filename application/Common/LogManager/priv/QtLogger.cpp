/**
  * 8LAN - A decentralized LAN file sharing software.
  * Copyright (C) 2010-2012 Greg Burri <greg.burri@gmail.com>, oct8l
  *
  * This program is free software: you can redistribute it and/or modify
  * it under the terms of the GNU General Public License as published by
  * the Free Software Foundation, either version 3 of the License, or
  * (at your option) any later version.
  *
  * This program is distributed in the hope that it will be useful,
  * but WITHOUT ANY WARRANTY; without even the implied warranty of
  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  * GNU General Public License for more details.
  *
  * You should have received a copy of the GNU General Public License
  * along with this program.  If not, see <http://www.gnu.org/licenses/>.
  */
  
#include <priv/QtLogger.h>
using namespace LM;

#include <QtGlobal>

#include <IEntry.h>

/**
  * @class LM::QtLogger
  *
  * A special objet is create to handle all Qt message. For example
  * when a signal is connected to an unknown slot, the warning will be
  * catched and logged here.
  * Warning, the Qt messages are not catched during unit tesing because 'QTest::qExec(..)'
  * will create its own handle and discard the current one.
  */

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
void handler(QtMsgType type, const QMessageLogContext&, const QString& msg)
#else
void handler(QtMsgType type, const char* msg)
#endif
{
   Severity s =
         type == QtDebugMsg ? SV_DEBUG :
         type == QtWarningMsg ? SV_WARNING :
         type == QtCriticalMsg ? SV_ERROR :
         type == QtFatalMsg ? SV_FATAL_ERROR : SV_UNKNOWN;

#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
   QtLogger::me.log(msg, s);
#else
   QtLogger::me.log(msg, s);
#endif
}

const QtLogger QtLogger::me;

/**
  * Fake class method to avoid the case where this compilation unit (.o)
  * is dropped by the linker when using 'libLogManager.a'.
  */
void QtLogger::initMsgHandler()
{
#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
   qInstallMessageHandler(handler);
#else
   qInstallMsgHandler(handler);
#endif
}

QtLogger::QtLogger() :
   Logger("Qt")
{
   QtLogger::initMsgHandler();
}
