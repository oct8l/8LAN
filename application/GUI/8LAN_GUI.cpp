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
  
#include <8LAN_GUI.h>
using namespace GUI;

#include <QMessageBox>
#include <QPushButton>
#include <QAction>

#include <Common/LogManager/Builder.h>
#include <Common/Constants.h>
#include <Common/Settings.h>
#include <Common/Languages.h>

#include <Common/RemoteCoreController/Builder.h>

const QString EightLAN_GUI::SHARED_MEMORY_KEYNAME("8LAN GUI instance");

/**
  * @class GUI::EightLAN_GUI
  * This class control the trayIcon and create the main window.
  * The main window can be hid and deleted, the tray icon will still remain and will permit to relaunch the main window.
  */

EightLAN_GUI::EightLAN_GUI(int& argc, char* argv[]) :
   QApplication(argc, argv),
   mainWindow(0),
   trayIcon(QIcon(":/icons/ressources/icon.png")),
   coreConnection(RCC::Builder::newCoreConnection(SETTINGS.get<quint32>("socket_timeout")))
{
   this->installTranslator(&this->translator);
   QLocale current = QLocale::system();
   if (SETTINGS.isSet("language"))
      current = SETTINGS.get<QLocale>("language");
   Common::Languages langs(QCoreApplication::applicationDirPath() + "/" + Common::Constants::LANGUAGE_DIRECTORY);
   this->loadLanguage(langs.getBestMatchLanguage(Common::Languages::ExeType::GUI, current).filename);

   // If multiple instance isn't allowed we will test if a particular
   // shared memory segment alreydy exists. There is actually no
   // easy way to bring the already existing GUI windows to the front without
   // dirty polling.
   // Under linux the flag may persist after process crash.
#ifndef Q_OS_LINUX
   if (!SETTINGS.get<bool>("multiple_instance_allowed"))
   {
      this->sharedMemory.lock();
      this->sharedMemory.setKey(SHARED_MEMORY_KEYNAME);
      if (!this->sharedMemory.create(1))
      {
         QMessageBox message;
         message.setWindowTitle(QObject::tr("8LAN already launched"));
         message.setText(QObject::tr("An instance of 8LAN is already launched"));
         message.setIcon(QMessageBox::Information);
         QAbstractButton* abortButton = message.addButton(QObject::tr("Quit"), QMessageBox::RejectRole);
         message.addButton(QObject::tr("Launch anyway"), QMessageBox::ActionRole);
         message.exec();
         if (message.clickedButton() == abortButton)
         {
            this->sharedMemory.unlock();
            QSharedPointer<LM::ILogger> mainLogger = LM::Builder::newLogger("8LAN GUI");
            mainLogger->log("GUI already launched, exiting . . .", LM::SV_END_USER);
            throw AbortException();
         }
      }
      this->sharedMemory.unlock();
   }
#endif

   this->setQuitOnLastWindowClosed(false);

   this->showMainWindow();

   RCC::ICoreConnection* coreConnectionPointer = this->coreConnection.data();
   connect(coreConnectionPointer, &RCC::ICoreConnection::localCoreStatusChanged, this, &EightLAN_GUI::updateTrayIconMenu);
   connect(coreConnectionPointer, &RCC::ICoreConnection::connected, this, &EightLAN_GUI::updateTrayIconMenu);
   connect(coreConnectionPointer, &RCC::ICoreConnection::disconnected, this, &EightLAN_GUI::updateTrayIconMenu);

   connect(&this->trayIcon, &QSystemTrayIcon::activated, this, &EightLAN_GUI::trayIconActivated);

   this->updateTrayIconMenu();

   this->trayIcon.setContextMenu(&this->trayIconMenu);
   #ifndef Q_OS_LINUX
      // Fix a bug on ubuntu x86_64 (core dumped)
      this->trayIcon.setToolTip("8LAN");
   #endif
   this->trayIcon.show();
}

bool EightLAN_GUI::event(QEvent* event)
{
   if (event->type() == QEvent::LanguageChange)
      this->updateTrayIconMenu();

   return QApplication::event(event);
}

void EightLAN_GUI::trayIconActivated(QSystemTrayIcon::ActivationReason reason)
{
   if (reason == QSystemTrayIcon::Trigger)
      this->showMainWindow();
}

void EightLAN_GUI::updateTrayIconMenu()
{
   this->trayIconMenu.clear();
   QAction* showGuiAction = this->trayIconMenu.addAction(tr("Show the GUI"));
   connect(showGuiAction, &QAction::triggered, this, &EightLAN_GUI::showMainWindow);
   if (this->coreConnection->getLocalCoreStatus() == RCC::RUNNING_AS_SERVICE) // We cannot stop a parent process without killing his child.
   {
      QAction* stopGuiAction = this->trayIconMenu.addAction(tr("Stop the GUI"));
      connect(stopGuiAction, &QAction::triggered, this, &EightLAN_GUI::exitGUI);
   }
   this->trayIconMenu.addSeparator();
   QAction* exitAction = this->trayIconMenu.addAction(tr("Exit"));
   connect(exitAction, &QAction::triggered, this, [this]() { this->exit(); });
}

/**
  * Load a translation file. If 'filename' is empty the default language is loaded.
  */
void EightLAN_GUI::loadLanguage(const QString& filename)
{
   (void)this->translator.load(filename, QCoreApplication::applicationDirPath() + "/" + Common::Constants::LANGUAGE_DIRECTORY);
}

void EightLAN_GUI::mainWindowClosed()
{
   if (this->coreConnection->isConnected())
      this->trayIcon.showMessage("8LAN GUI closed", "8LAN Core is still running in background. Select 'exit' from the contextual menu if you want to stop it.");
   this->coreConnection->disconnectFromCore();
   this->mainWindow = nullptr;
}

void EightLAN_GUI::showMainWindow()
{
   if (this->mainWindow)
   {
      this->mainWindow->setWindowState(Qt::WindowActive);
      this->mainWindow->raise();
      this->mainWindow->activateWindow();
   }
   else
   {
      this->mainWindow = new MainWindow(this->coreConnection);
      connect(this->mainWindow, &MainWindow::languageChanged, this, &EightLAN_GUI::loadLanguage);
      connect(this->mainWindow, &QObject::destroyed, this, &EightLAN_GUI::mainWindowClosed);
      this->mainWindow->show();
   }
}

/**
  * Stop only the GUI.
  */
void EightLAN_GUI::exitGUI()
{
   this->exit(false);
}

void EightLAN_GUI::exit(bool stopTheCore)
{
   this->trayIcon.hide();

   if (stopTheCore)
      this->coreConnection->stopLocalCore();

   if (this->mainWindow)
   {
      disconnect(this->mainWindow, &QObject::destroyed, this, &EightLAN_GUI::mainWindowClosed);
      delete this->mainWindow;
   }

   this->quit();
}
