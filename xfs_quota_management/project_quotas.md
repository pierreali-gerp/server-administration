# Gestione quote XFS basata su _projects_

## Associazione _project quota_ XFS alla _home_ di un nuovo utente

**I comandi che seguono devono essere eseguiti da un utente con privilegi di amministratore** (o preceduti da _sudo_).

Definisco il nome del nuovo utente (già creato), alla cui home voglio associare la _project quota_ di interesse
```
UNAME=pippo
```

Creo la cartella home dell'utente a cui verrà associato un suo specifico project e gli associo i relativi permessi (se non è stata ancora creata)
```
mkdir /home/$UNAME
chown $UNAME:$UNAME -R /home/$UNAME
chmod 700 -R /home/$UNAME
```

Configuro i projects per xfs. Se i file di configurazione _/etc/projects_ e _/etc/projid_ ancora non esistono, verranno creati: nel primo, aggiungo ID e path del progetto; nel secondo, si associa un nome del progetto all'ID. Per semplicità, utilizzo lo stesso _user ID_ come ID da assegnare al progetto della home del singolo utente.
> ⚠️ Do per scontato che, **ogni qualvolta un utente viene rimosso dal sistema** (con uno script _del_user.sh_ apposito), **anche le entries relative alla sua home vengano rimosse dalle quote di progetto**! La sezione successiva mostra come ciò possa essere fatto.
```
PROJID=$(id -u $UNAME)
PROJNAME=home$UNAME
echo "$PROJID:/home/$UNAME" >> /etc/projects
echo "$PROJNAME:$PROJID" >> /etc/projid
```

Inizializzo il progetto all'interno del filesystem xfs scelto. Il path indicato in fondo (_/home_, in questo caso) e' il punto di mount del file system xfs. Uso il nome del progetto assegnato in _/etc/projid_
```
xfs_quota -x -c "project -s $PROJNAME" /home
```

Setto le quotas per il progetto (-p) appena inizializzato (ad esempio, soft limit a 150GB e hard limit a 200GB)
```
xfs_quota -x -c "limit -p bsoft=150g bhard=200g $PROJNAME" /home
```


## Rimozione _project quota_ XFS dalla _home_ di un utente che si desidera rimuovere

**I comandi che seguono devono essere eseguiti da un utente con privilegi di amministratore** (o preceduti da _sudo_).

> ⚠️ La **rimozione del _project_** associato a una cartella andrebbe svolta **prima di rimuovere la cartella di progetto**. La rimozione del project non comporta la cancellazione dei files contenuti in questa cartella, ma solo la rimozione della directory dalla gestione quote di xfs.

Definisco il nome dell'utente del quale desideriamo rimuovere la _project quota_ associata alla sua home e compongo nome e ID del relativo project in base alle scelte fatte nella sezione precedente
```
UNAME=pippo
PROJNAME=home$UNAME
PROJID=$(id -u $UNAME)
```

Rimuovo dalla gestione quote del project (opzione -C, che sta per "clear") file e directories (che, assieme, costituiscono gli inodes del project) attualmente presenti nella cartella home dell'utente
```
xfs_quota -x -c "project -C $PROJNAME" /home
```

Rimuovo i limiti fissati per il progetto (da fare PRIMA dello step successivo per potersi ancora riferire al project con il nome assegnato)

```
xfs_quota -x -c "limit -p bsoft=0 bhard=0 $PROJNAME" /home

```

Ora che ho rimosso qualsiasi riferimento al project che voglio non considerare più, posso andare a rimuoverlo da _/etc/projects_ e _/etc/projid_. In entrambi i files, cancello la riga associata al project.
**NB:** Questo blocco non l'ho mai testato in automatico sui projects, ma funziona correttamente su file di prova: effettuare un ultimo test su una copia dei files in questione prima di mettere in produzione!
```
sed -i "/^$PROJNAME:/d" /etc/projid
sed -i "/^$PROJID:/d" /etc/projects
```

Ora, se serve, posso andare a rimuovere la directory precedentemente associata al progetto e tutti i file in essa contenuti
```
rm -Rd /home/$UNAME

# In alternativa, per rimuovere direttamente l'utente e la relativa home in modo più sicuro:
userdel -r $UNAME
```
