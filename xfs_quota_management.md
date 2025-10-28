Creo la cartella home dell'utente a cui verrà associato un suo specifico project e gli associo i relativi permessi

```
sudo mkdir /home/$USERNAME
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME
```

Configuro i projects per xfs (se questi files ancora non esistono, verranno creati). Per semplicità, utilizzo lo user ID come ID da assegnare al progetto della home del singolo utente.

```
PROJID=$(id -u $USERNAME)
sudo echo "$PROJID:/home/$USERNAME" >> etc/projects # Qui aggiungo ID e path del progetto
PROJNAME=home$USERNAME
sudo echo "$PROJNAME:$PROJID" >> /etc/projid # Qui aggiungo il nome del progetto associato all'ID
```

Inizializzo il progetto all'interno del filesystem xfs scelto (il path in fondo e' il punto di mount del file system xfs); uso il nome del progetto assegnato in /etc/projid

```
sudo xfs_quota -x -c 'project -s $PROJNAME' /home
```

Setto le quotas per il progetto (-p) appena inizializzato (ad esempio, soft limit a 1000GB e hard limit a 1300GB)

```
sudo xfs_quota -x -c 'limit -p bsoft=1000g bhard=1300g $PROJNAME' /home
```
