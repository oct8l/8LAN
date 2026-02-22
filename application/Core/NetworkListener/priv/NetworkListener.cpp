/**
  * D-LAN - A decentralized LAN file sharing software.
  * Copyright (C) 2010-2012 Greg Burri <greg.burri@gmail.com>
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
  
#include <priv/NetworkListener.h>
using namespace NL;

#include <QNetworkAddressEntry>
#include <QNetworkInterface>

#include <Common/LogManager/Builder.h>

#include <priv/Chat.h>
#include <priv/Search.h>

LOG_INIT_CPP(NetworkListener);

namespace
{
   QSet<QString> getActiveNetworkInterfacesSnapshot()
   {
      QSet<QString> interfacesSnapshot;
      const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
      for (int i = 0; i < interfaces.size(); ++i)
      {
         const QNetworkInterface& interface = interfaces[i];
         if (!(interface.flags() & QNetworkInterface::IsUp))
            continue;

         const QList<QNetworkAddressEntry> addressEntries = interface.addressEntries();
         for (int j = 0; j < addressEntries.size(); ++j)
         {
            const QHostAddress ipAddress = addressEntries[j].ip();
            if (ipAddress.protocol() == QAbstractSocket::IPv4Protocol || ipAddress.protocol() == QAbstractSocket::IPv6Protocol)
               interfacesSnapshot.insert(interface.name() + "|" + ipAddress.toString());
         }
      }
      return interfacesSnapshot;
   }
}

NetworkListener::NetworkListener(
   QSharedPointer<FM::IFileManager> fileManager,
   QSharedPointer<PM::IPeerManager> peerManager,
   QSharedPointer<UM::IUploadManager> uploadManager,
   QSharedPointer<DM::IDownloadManager> downloadManager
) :
   fileManager(fileManager),
   peerManager(peerManager),
   uploadManager(uploadManager),
   downloadManager(downloadManager),
   tCPListener(peerManager),
   uDPListener(fileManager, peerManager, uploadManager, downloadManager, tCPListener.getCurrentPort()),
   chat(uDPListener)
{
   this->networkInterfacesSnapshot = getActiveNetworkInterfacesSnapshot();
   this->networkPollTimer.setInterval(3000);
   connect(&this->networkPollTimer, &QTimer::timeout, this, &NetworkListener::pollNetworkInterfaces);
   this->networkPollTimer.start();
}

NetworkListener::~NetworkListener()
{
   this->uDPListener.send(Common::MessageHeader::CORE_GOODBYE);
   L_DEBU("NetworkListener deleted");
}

IChat& NetworkListener::getChat()
{
   return this->chat;
}

QSharedPointer<ISearch> NetworkListener::newSearch()
{
   return QSharedPointer<ISearch>(new Search(this->uDPListener));
}

void NetworkListener::rebindSockets()
{
   this->peerManager->removeAllPeers();
   this->uDPListener.rebindSockets();
   this->tCPListener.rebindSockets();
}

void NetworkListener::pollNetworkInterfaces()
{
   const QSet<QString> currentSnapshot = getActiveNetworkInterfacesSnapshot();
   if (currentSnapshot != this->networkInterfacesSnapshot)
   {
      this->networkInterfacesSnapshot = currentSnapshot;
      this->rebindSockets();
   }
}
