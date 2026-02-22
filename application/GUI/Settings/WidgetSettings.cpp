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
  
#include <Settings/WidgetSettings.h>
#include <ui_WidgetSettings.h>
using namespace GUI;

#include <QFileDialog>
#include <QTranslator>
#include <QMessageBox>
#include <QListView>
#include <QLabel>
#include <QMenu>
#include <QAction>
#include <QAbstractButton>
#include <QComboBox>
#include <QLineEdit>
#include <QDesktopServices>
#include <QUrl>
#include <QStringBuilder>

#include <Common/Languages.h>
#include <Common/Constants.h>
#include <Common/ProtoHelper.h>
#include <Common/Settings.h>

#include <Protos/gui_settings.pb.h>

#include <Utils.h>

void DirListDelegate::paint(QPainter* painter, const QStyleOptionViewItem& option, const QModelIndex& index) const
{
   QStyleOptionViewItem newOption(option);
   newOption.state = option.state & (~QStyle::State_HasFocus);
   QStyledItemDelegate::paint(painter, newOption, index);
}

/////

WidgetSettings::WidgetSettings(QSharedPointer<RCC::ICoreConnection> coreConnection, DirListModel& sharedDirsModel, QWidget* parent) :
   QWidget(parent), ui(new Ui::WidgetSettings), getAtLeastOneState(false), coreConnection(coreConnection), sharedDirsModel(sharedDirsModel), corePasswordDefined(false)
{
   this->ui->setupUi(this);

   this->ui->tblShareDirs->setItemDelegate(&this->dirListDelegate);
   this->ui->tblShareDirs->setModel(&this->sharedDirsModel);
   this->ui->tblShareDirs->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
   this->ui->tblShareDirs->horizontalHeader()->setSectionResizeMode(1, QHeaderView::ResizeToContents);
   this->ui->tblShareDirs->horizontalHeader()->setSectionResizeMode(2, QHeaderView::ResizeToContents);
#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
   this->ui->tblShareDirs->horizontalHeader()->setSectionsClickable(false);
#else
   this->ui->tblShareDirs->horizontalHeader()->setClickable(false);
#endif
   this->ui->tblShareDirs->horizontalHeader()->setVisible(true);

   this->ui->tblShareDirs->verticalHeader()->setSectionResizeMode(QHeaderView::Fixed);
   this->ui->tblShareDirs->verticalHeader()->setDefaultSectionSize(QFontMetrics(qApp->font()).height() + 2);
   this->ui->tblShareDirs->verticalHeader()->setVisible(false);
   this->ui->tblShareDirs->setSelectionBehavior(QAbstractItemView::SelectRows);
   this->ui->tblShareDirs->setSelectionMode(QAbstractItemView::SingleSelection);
   this->ui->tblShareDirs->setShowGrid(false);
   this->ui->tblShareDirs->setAlternatingRowColors(true);

   this->ui->txtCoreAddress->setText(SETTINGS.get<QString>("core_address"));
   connect(this->ui->txtCoreAddress, &QLineEdit::returnPressed, this->ui->butConnect, &QAbstractButton::click);
   connect(this->ui->txtPassword, &QLineEdit::returnPressed, this->ui->butConnect, &QAbstractButton::click);

   connect(this->coreConnection.data(), &RCC::ICoreConnection::newState, this, &WidgetSettings::newState);
   connect(this->coreConnection.data(), &RCC::ICoreConnection::connecting, this, &WidgetSettings::coreConnecting);
   connect(this->coreConnection.data(), &RCC::ICoreConnection::connectingError, this, &WidgetSettings::coreConnectingError);
   connect(this->coreConnection.data(), &RCC::ICoreConnection::connected, this, &WidgetSettings::coreConnected);
   connect(this->coreConnection.data(), &RCC::ICoreConnection::disconnected, this, &WidgetSettings::coreDisconnected);

   connect(this->ui->txtNick, &QLineEdit::editingFinished, this, &WidgetSettings::saveCoreSettings);

   connect(this->ui->chkEnableIntegrityCheck, &QAbstractButton::clicked, this, &WidgetSettings::saveCoreSettings);
   connect(this->ui->butRefreshInterfaces, &QAbstractButton::clicked, this, &WidgetSettings::refreshNetworkInterfaces);

   this->connectAllAddressButtons();

   connect(this->ui->butAddShared, &QAbstractButton::clicked, this, &WidgetSettings::addShared);
   connect(this->ui->butRemoveShared, &QAbstractButton::clicked, this, &WidgetSettings::removeShared);

   connect(this->ui->butMoveUpShared, &QAbstractButton::clicked, this, &WidgetSettings::moveUpShared);
   connect(this->ui->butMoveDownShared, &QAbstractButton::clicked, this, &WidgetSettings::moveDownShared);

   connect(this->ui->butOpenFolder, &QAbstractButton::clicked, this, &WidgetSettings::openLocation);

   connect(this->ui->butResetCoreAddress, &QAbstractButton::clicked, this, &WidgetSettings::resetCoreAddress);
   connect(this->ui->butConnect, &QAbstractButton::clicked, this, &WidgetSettings::connectToCore);
   connect(this->ui->butDisconnect, &QAbstractButton::clicked, this, &WidgetSettings::disconnectFromTheCore);
   this->ui->tabAdvancedSettings->installEventFilter(this);

   this->ui->tblShareDirs->setContextMenuPolicy(Qt::CustomContextMenu);
   connect(this->ui->tblShareDirs, &QWidget::customContextMenuRequested, this, &WidgetSettings::displayContextMenuSharedDirs);

   // When the selection change or a shared dir is moved/deleted/inserted we must set the availability of the action buttons.
   connect(this->ui->tblShareDirs->selectionModel(), &QItemSelectionModel::selectionChanged, this, static_cast<void (WidgetSettings::*)(const QItemSelection&)>(&WidgetSettings::refreshButtonsAvailability));
   connect(&this->sharedDirsModel, &QAbstractItemModel::layoutChanged, this, static_cast<void (WidgetSettings::*)()>(&WidgetSettings::refreshButtonsAvailability));
   connect(&this->sharedDirsModel, &QAbstractItemModel::rowsInserted, this, static_cast<void (WidgetSettings::*)()>(&WidgetSettings::refreshButtonsAvailability));
   connect(&this->sharedDirsModel, &QAbstractItemModel::rowsRemoved, this, static_cast<void (WidgetSettings::*)()>(&WidgetSettings::refreshButtonsAvailability));

   this->fillComboBoxLanguages();
   connect(this->ui->cmbLanguages, static_cast<void (QComboBox::*)(int)>(&QComboBox::currentIndexChanged), this, &WidgetSettings::cmbLanguageChanged);

   this->fillComboBoxStyles();
   connect(this->ui->cmbStyles, static_cast<void (QComboBox::*)(int)>(&QComboBox::currentIndexChanged), this, &WidgetSettings::cmbStyleChanged);
   connect(this->ui->butReloadStyle, &QAbstractButton::clicked, this, &WidgetSettings::reloadCurrentStyle);

   connect(this->ui->butChangePassword, &QAbstractButton::clicked, this, &WidgetSettings::changePassword);
   connect(this->ui->butResetPassword, &QAbstractButton::clicked, this, &WidgetSettings::resetPassword);

   this->refreshButtonsAvailability();
   this->coreDisconnected(); // To set the initial state.
}

WidgetSettings::~WidgetSettings()
{
   delete this->ui;
}

void WidgetSettings::resetCoreAddress()
{
   this->ui->txtCoreAddress->setText("localhost");
   this->connectToCore();
}

void WidgetSettings::connectToCore()
{
   const QString newHost = this->ui->txtCoreAddress->text().trimmed().toLower();

   if (newHost != SETTINGS.get<QString>("core_address") || !this->coreConnection->isConnected())
      this->coreConnection->connectToCore(newHost, SETTINGS.get<quint32>("core_port"), this->ui->txtPassword->text());
}

void WidgetSettings::disconnectFromTheCore()
{
   this->coreConnection->disconnectFromCore();
   SETTINGS.rm("password");
   SETTINGS.save();
}

/**
  * Read the available language files and fill the combo box.
  */
void WidgetSettings::fillComboBoxLanguages()
{
   QVariant dataEn;
   dataEn.setValue(Common::Language { "", QLocale("en") });
   this->ui->cmbLanguages->addItem("English", dataEn);

   QLocale current = QLocale::system();
   if (SETTINGS.isSet("language"))
      current = SETTINGS.get<QLocale>("language");

   this->coreConnection->setCoreLanguage(current);

   bool exactMatchFound = false;

   Common::Languages langs(QCoreApplication::applicationDirPath() + "/" + Common::Constants::LANGUAGE_DIRECTORY);
   for (QListIterator<Common::Language> i(langs.getAvailableLanguages(Common::Languages::ExeType::GUI)); i.hasNext();)
   {
      Common::Language lang = i.next();
      QVariant data;
      data.setValue(lang);
      this->ui->cmbLanguages->addItem(lang.locale.nativeLanguageName(), data);

      if (!exactMatchFound && lang.locale.language() == current.language())
      {
#if QT_VERSION >= QT_VERSION_CHECK(6, 2, 0)
         exactMatchFound = lang.locale.territory() == current.territory();
#else
         exactMatchFound = lang.locale.country() == current.country();
#endif
         this->ui->cmbLanguages->setCurrentIndex(this->ui->cmbLanguages->count() - 1);
      }
   }
}

void WidgetSettings::fillComboBoxStyles()
{
   const QString& currentStyleFilename = SETTINGS.get<QString>("style");

   this->ui->cmbStyles->addItem(tr("Default"));

   const QDir styleDir(QCoreApplication::applicationDirPath() + "/" + Common::Constants::STYLE_DIRECTORY);
   for (QStringListIterator i(styleDir.entryList(QDir::Dirs | QDir::NoSymLinks | QDir::NoDotAndDotDot, QDir::Name)); i.hasNext();)
   {
      const QString& dirname = i.next();
      this->ui->cmbStyles->addItem(dirname, dirname);
      if (currentStyleFilename == dirname)
         this->ui->cmbStyles->setCurrentIndex(this->ui->cmbStyles->count() - 1);
   }
}

void WidgetSettings::connectAllAddressButtons()
{
   for (QListIterator<QRadioButton*> i(this->ui->scoInterfacesContent->findChildren<QRadioButton*>()); i.hasNext();)
      connect(i.next(), &QAbstractButton::toggled, this, &WidgetSettings::buttonAddressToggled);
}

void WidgetSettings::disconnectAllAddressButtons()
{
   for (QListIterator<QRadioButton*> i(this->ui->scoInterfacesContent->findChildren<QRadioButton*>()); i.hasNext();)
      i.next()->disconnect(this);
}

void WidgetSettings::updateNetworkInterfaces(const Protos::GUI::State& state)
{
   this->disconnectAllAddressButtons();

   QList<QLabel*> interfaceNotUpdated = this->ui->scoInterfacesContent->findChildren<QLabel*>("");

   for (int i = 0; i < state.interface_size(); i++)
   {
      const QString& interfaceName = Common::ProtoHelper::getStr(state.interface(i), &Protos::Common::Interface::name);

      for (QListIterator<QObject*> j(this->ui->scoInterfacesContent->children()); j.hasNext();)
      {
         QLabel* lblInterface = dynamic_cast<QLabel*>(j.next());
         if (lblInterface && lblInterface->property("id").toUInt() == state.interface(i).id())
         {
            interfaceNotUpdated.removeOne(lblInterface);
            lblInterface->setText(interfaceName + (state.interface(i).isup() ? "" : " <img src= \":/icons/ressources/error.png\" /> <em>" + tr("Interface not active") + "</em>"));
            this->updateAddresses(state.interface(i), static_cast<QWidget*>(j.next()));
            goto nextInterface;
         }
      }

      {
         // Interface not found -> add a new one.
         QLabel* label = new QLabel(interfaceName, this->ui->scoInterfacesContent);
         label->setProperty("id", state.interface(i).id());
         this->ui->layInterfaces->addWidget(label);
         QWidget* addressesContainer = new QWidget(this->ui->scoInterfacesContent);
         this->ui->layInterfaces->addWidget(addressesContainer);
         this->updateAddresses(state.interface(i), addressesContainer);
      }

      nextInterface:;
   }

   // Remove the non-existant interfaces.
   for (QListIterator<QObject*> i(this->ui->scoInterfacesContent->children()); i.hasNext();)
   {
      QLabel* current = dynamic_cast<QLabel*>(i.next());
      if (current && interfaceNotUpdated.contains(current))
      {
         this->ui->layInterfaces->removeWidget(current);
         QWidget* addressesContainer = dynamic_cast<QWidget*>(i.next());
         this->ui->layInterfaces->removeWidget(addressesContainer);
         delete current;
         delete addressesContainer;
      }
   }

   // Set the current address.
   if (state.has_listenany())
   {
      if (state.listenany() == Protos::Common::Interface::Address::IPv6)
         this->ui->radIPv6->setChecked(true);
      else
         this->ui->radIPv4->setChecked(true);
   }

   this->connectAllAddressButtons();
}

void WidgetSettings::updateAddresses(const Protos::Common::Interface& interface, QWidget* container)
{
   QVBoxLayout* layout = container->findChild<QVBoxLayout*>();
   if (!layout)
   {
      layout = new QVBoxLayout(container);
      QMargins margins = layout->contentsMargins();
      margins.setTop(3);
      layout->setContentsMargins(margins);
   }

   QList<QRadioButton*> addressesNotUpdated = container->findChildren<QRadioButton*>();

   for (int i = 0; i < interface.address_size(); i++)
   {
      const QString& addresseName = Common::ProtoHelper::getStr(interface.address(i), &Protos::Common::Interface::Address::address);

      for (QListIterator<QRadioButton*> j(container->findChildren<QRadioButton*>()); j.hasNext();)
      {
         QRadioButton* addressButton = j.next();
         if (addressButton->text() == addresseName)
         {
            addressesNotUpdated.removeOne(addressButton);
            if (interface.address(i).listened())
               addressButton->setChecked(true);
            goto nextAddress;
         }
      }

      {
         // Address not found -> add a new one.
         QRadioButton* newAddressButton = new QRadioButton(addresseName, container);
         this->ui->grpAddressesToListenTo->addButton(newAddressButton);
         if (interface.address(i).listened())
            newAddressButton->setChecked(true);
         layout->addWidget(newAddressButton);
      }

      nextAddress:;
   }

   // Remove the non-existant addresses.
   for (QListIterator<QRadioButton*> i(container->findChildren<QRadioButton*>()); i.hasNext();)
   {
      QRadioButton* current = i.next();
      if (addressesNotUpdated.contains(current))
      {
         layout->removeWidget(current);
         this->ui->grpAddressesToListenTo->removeButton(current);
         delete current;
      }
   }
}

void WidgetSettings::newState(const Protos::GUI::State& state)
{
   if (!this->ui->txtNick->hasFocus())
      this->ui->txtNick->setText(Common::ProtoHelper::getStr(state.peer(0), &Protos::GUI::State_Peer::nick));

   if (!this->ui->chkEnableIntegrityCheck->hasFocus())
      this->ui->chkEnableIntegrityCheck->setChecked(state.integrity_check_enabled());

   if (this->corePasswordDefined = state.password_defined())
   {
      this->ui->txtPassword->setPlaceholderText("");
      this->ui->butResetPassword->setEnabled(true);
      this->ui->butChangePassword->setText(tr("Change the password"));
   }
   else
   {
      this->ui->txtPassword->setPlaceholderText("No password defined");
      this->ui->butResetPassword->setEnabled(false);
      this->ui->butChangePassword->setText(tr("Define a password"));
   }

   QList<Common::SharedDir> sharedDirs;
   for (int i = 0; i < state.shared_directory_size(); i++)
      sharedDirs <<
         Common::SharedDir {
            state.shared_directory(i).id().hash(),
            Common::ProtoHelper::getStr(state.shared_directory(i), &Protos::GUI::State_SharedDir::path),
            (qint64)state.shared_directory(i).size(),
            (qint64)state.shared_directory(i).free_space()
         };
   this->sharedDirsModel.setDirs(sharedDirs);

   this->updateNetworkInterfaces(state);

   this->getAtLeastOneState = true;


   // If this is the first message state received and there is no incoming folder defined we ask the user to choose one.
   // Commented cuz the user can know choose a folder right before downloading a file.
   /*if (this->initialState)
   {
      this->initialState = false;
      if (this->sharedDirsModel.rowCount() == 0)
      {
         if (QMessageBox::question(
               this,
               "No directory folder",
               "You don't have any shared directory, would you like to choose one?",
               QMessageBox::Yes,
               QMessageBox::No
            ) == QMessageBox::Yes)
         {
            this->addShared();
         }
      }
   }*/
}

void WidgetSettings::coreConnecting()
{
   this->ui->butConnect->setDisabled(true);
   this->ui->butDisconnect->setDisabled(true);
   this->ui->butResetCoreAddress->setDisabled(true);
   this->ui->butConnect->setText(tr("Connecting.."));
}

void WidgetSettings::coreConnectingError()
{
   this->ui->butConnect->setDisabled(false);
   this->ui->butDisconnect->setDisabled(!this->coreConnection->isConnected());
   this->ui->butResetCoreAddress->setDisabled(false);
   this->ui->butConnect->setText(tr("Connect"));
}

void WidgetSettings::coreConnected()
{
   SETTINGS.set("core_address", this->coreConnection->getConnectionInfo().address);
   SETTINGS.set("core_port", static_cast<quint32>(this->coreConnection->getConnectionInfo().port));
   SETTINGS.set("password", this->coreConnection->getConnectionInfo().password);
   SETTINGS.save();

   this->ui->txtPassword->clear();
   this->ui->tabWidget->setTabEnabled(0, true);
   this->ui->tabWidget->setTabEnabled(1, true);
   this->ui->chkEnableIntegrityCheck->setEnabled(true);

   this->ui->butConnect->setDisabled(false);
   this->ui->butConnect->setText(tr("Connect"));
   this->ui->butDisconnect->setDisabled(false);
   this->ui->butResetCoreAddress->setDisabled(false);

   this->ui->butChangePassword->setDisabled(false);

   this->ui->butOpenFolder->setDisabled(!this->coreConnection->isLocal());
}

void WidgetSettings::coreDisconnected()
{
   this->getAtLeastOneState = false;

   this->ui->tabWidget->setTabEnabled(0, false);
   this->ui->tabWidget->setTabEnabled(1, false);
   this->ui->chkEnableIntegrityCheck->setEnabled(false);

   this->ui->butConnect->setDisabled(false);
   this->ui->butConnect->setText(tr("Connect"));
   this->ui->butDisconnect->setDisabled(true);

   this->ui->butChangePassword->setDisabled(true);
   this->ui->butResetPassword->setDisabled(true);
}

void WidgetSettings::refreshNetworkInterfaces()
{
   this->coreConnection->refreshNetworkInterfaces();
}

/**
  * Send the settings to the core. A connection to a core must be established.
  */
void WidgetSettings::saveCoreSettings()
{
   if (!this->getAtLeastOneState)
      return;

   Protos::GUI::CoreSettings settings;
   Common::ProtoHelper::setStr(settings, &Protos::GUI::CoreSettings::set_nick, this->ui->txtNick->text());
   settings.set_enable_integrity_check(this->ui->chkEnableIntegrityCheck->isChecked());

   for (QListIterator<Common::SharedDir> i(this->sharedDirsModel.getDirs()); i.hasNext();)
      Common::ProtoHelper::addRepeatedStr(*settings.mutable_shared_directories(), &Protos::GUI::CoreSettings::SharedDirectories::add_dir, i.next().path);

   if (this->ui->radIPv6->isChecked())
      settings.set_listen_any(Protos::Common::Interface::Address::IPv6);
   else if (this->ui->radIPv4->isChecked())
      settings.set_listen_any(Protos::Common::Interface::Address::IPv4);
   else
   {
      for (QListIterator<QRadioButton*> i(this->ui->grpInterfaces->findChildren<QRadioButton*>()); i.hasNext();)
      {
         QRadioButton* button = i.next();
         if (button->isChecked())
         {
            Common::ProtoHelper::setStr(settings, &Protos::GUI::CoreSettings::set_listen_address, button->text());
            break;
         }
      }
   }

   this->coreConnection->setCoreSettings(settings);
}

void WidgetSettings::cmbLanguageChanged(int cmbIndex)
{
   const Common::Language& lang = this->ui->cmbLanguages->itemData(cmbIndex).value<Common::Language>();
   emit languageChanged(lang.filename);
   this->coreConnection->setCoreLanguage(lang.locale);
   SETTINGS.set("language", this->ui->cmbLanguages->itemData(this->ui->cmbLanguages->currentIndex()).value<Common::Language>().locale);
   SETTINGS.save();
}

void WidgetSettings::cmbStyleChanged(int cmbIndex)
{
   const QString& dirname = this->ui->cmbStyles->itemData(cmbIndex).toString();
   emit styleChanged(dirname.isEmpty() ? QString() : QCoreApplication::applicationDirPath() % "/" % Common::Constants::STYLE_DIRECTORY % "/" % dirname % "/" % Common::Constants::STYLE_FILE_NAME);
   SETTINGS.set("style", dirname);
   SETTINGS.save();
}

void WidgetSettings::reloadCurrentStyle()
{
   const QString& dirname = this->ui->cmbStyles->itemData(this->ui->cmbStyles->currentIndex()).toString();
   emit styleChanged(dirname.isEmpty() ? QString() : QCoreApplication::applicationDirPath() % "/" % Common::Constants::STYLE_DIRECTORY % "/" % dirname % "/" % Common::Constants::STYLE_FILE_NAME);
}

void WidgetSettings::changePassword()
{
   AskNewPasswordDialog dia(this->coreConnection, this->corePasswordDefined, this);
   dia.exec();
}

void WidgetSettings::resetPassword()
{
   this->coreConnection->resetCorePassword();
   if (!this->coreConnection->isLocal())
      this->coreConnection->disconnectFromCore();
}

void WidgetSettings::addShared()
{
   QStringList dirs = Utils::askForDirectories(this->coreConnection);
   if (!dirs.isEmpty())
   {
      this->sharedDirsModel.addDirs(dirs);
      this->saveCoreSettings();
   }
}

void WidgetSettings::removeShared()
{
   QModelIndex index = this->ui->tblShareDirs->selectionModel()->currentIndex();
   if (index.isValid())
   {
      QMessageBox msgBox(this);
      msgBox.setWindowTitle("Remove selected shared directory");
      msgBox.setText("Are you sure to remove the selected shared directory? All computed hashes will be lost.");
      msgBox.setIcon(QMessageBox::Question);
      msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
      msgBox.setDefaultButton(QMessageBox::Ok);
      if (msgBox.exec() == QMessageBox::Ok)
      {
         this->sharedDirsModel.rmDir(index.row());
         this->saveCoreSettings();
      }
   }
}

void WidgetSettings::moveUpShared()
{
   QModelIndex index = this->ui->tblShareDirs->selectionModel()->currentIndex();
   if (index.isValid())
   {
      this->sharedDirsModel.mvUpDir(index.row());
      this->saveCoreSettings();
   }
}

void WidgetSettings::moveDownShared()
{
   QModelIndex index = this->ui->tblShareDirs->selectionModel()->currentIndex();
   if (index.isValid())
   {
      this->sharedDirsModel.mvDownDir(index.row());
      this->saveCoreSettings();
   }
}

void WidgetSettings::displayContextMenuSharedDirs(const QPoint& point)
{
   QPoint globalPosition = this->ui->tblShareDirs->mapToGlobal(point);
   globalPosition.setY(globalPosition.y() + this->ui->tblShareDirs->horizontalHeader()->height());

   QMenu menu;
   QAction* actionDelete = menu.addAction(QIcon(":/icons/ressources/delete.png"), tr("Remove the shared directory"));
   connect(actionDelete, &QAction::triggered, this, &WidgetSettings::removeShared);
   QAction* actionUp = menu.addAction(QIcon(":/icons/ressources/arrow_up.png"), tr("Move up"));
   connect(actionUp, &QAction::triggered, this, &WidgetSettings::moveUpShared);
   QAction* actionDown = menu.addAction(QIcon(":/icons/ressources/arrow_down.png"), tr("Move down"));
   connect(actionDown, &QAction::triggered, this, &WidgetSettings::moveDownShared);

   if (this->coreConnection->isLocal() && this->sharedDirsModel.rowCount() > 0)
   {
      QAction* openLocationAction = menu.addAction(QIcon(":/icons/ressources/explore_folder.png"), tr("Open location"));
      connect(openLocationAction, &QAction::triggered, this, &WidgetSettings::openLocation);
   }

   if (this->sharedDirsModel.rowCount() == 0)
      actionDelete->setDisabled(true);

   if (this->ui->tblShareDirs->currentIndex().row() == 0 || this->sharedDirsModel.rowCount() == 0)
      actionUp->setDisabled(true);

   if (this->ui->tblShareDirs->currentIndex().row() >= this->sharedDirsModel.rowCount() - 1  || this->sharedDirsModel.rowCount() == 0)
      actionDown->setDisabled(true);

   menu.exec(globalPosition);
}

void WidgetSettings::refreshButtonsAvailability(const QItemSelection& selected)
{
   if (selected.indexes().isEmpty() || !selected.indexes().first().isValid())
   {
      this->ui->butMoveUpShared->setDisabled(true);
      this->ui->butMoveDownShared->setDisabled(true);
      this->ui->butRemoveShared->setDisabled(true);
      this->ui->butOpenFolder->setDisabled(true);
   }
   else
   {
      this->ui->butMoveUpShared->setDisabled(selected.indexes().first().row() == 0);
      this->ui->butMoveDownShared->setDisabled(selected.indexes().first().row() == this->sharedDirsModel.rowCount() - 1);
      this->ui->butRemoveShared->setDisabled(false);
      this->ui->butOpenFolder->setDisabled(!this->coreConnection->isLocal());
   }
}

void WidgetSettings::refreshButtonsAvailability()
{
   this->refreshButtonsAvailability(QItemSelection(this->ui->tblShareDirs->selectionModel()->selection()));
}

void WidgetSettings::openLocation()
{
   QModelIndexList selectedRows = this->ui->tblShareDirs->selectionModel()->selectedRows();
   for (const auto& index : selectedRows)
      QDesktopServices::openUrl(QUrl("file:///" + this->sharedDirsModel.getLocationPath(index), QUrl::TolerantMode));
}

void WidgetSettings::buttonAddressToggled(bool checked)
{
   if (checked)
      this->saveCoreSettings();
}

bool WidgetSettings::eventFilter(QObject* obj, QEvent* event)
{
   if (obj == this->ui->tabAdvancedSettings && event->type() == QEvent::Show)
   {
      this->ui->txtPassword->clear();
      this->ui->txtCoreAddress->setText(SETTINGS.get<QString>("core_address"));
   }

   return QObject::eventFilter(obj, event);
}

void WidgetSettings::showEvent(QShowEvent* event)
{
   if (this->ui->tabWidget->isTabEnabled(0))
      this->ui->tabWidget->setCurrentIndex(0);

   QWidget::showEvent(event);
}

void WidgetSettings::changeEvent(QEvent* event)
{
   if (event->type() == QEvent::LanguageChange)
      this->ui->retranslateUi(this);
   else
      QWidget::changeEvent(event);
}
