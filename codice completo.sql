DROP DATABASE IF EXISTS officina;
CREATE DATABASE officina;
connect officina;
------------------------------


SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS Persone;
CREATE TABLE Persone(
CF varchar(16) primary key,
Nome char(10) not null,
Cognome char(10) not null,
Email varchar(40),
Cellulare varchar(15) not null
);

DROP TABLE IF EXISTS Veicolo;
CREATE TABLE Veicolo(
Targa varchar (7) PRIMARY KEY,
Marca char(15)not null,
Modello varchar(15)not null,
Versione varchar (100)not null,
Proprietario varchar (16),
FOREIGN KEY (Proprietario) REFERENCES Persone (CF)
ON UPDATE CASCADE 
);

DROP TABLE IF EXISTS Dipendente;
CREATE TABLE Dipendente(
Matricola smallint (2) primary key,
CF varchar(16),
Mansione ENUM('Segretario','Meccanico') not null,
FOREIGN KEY(CF) REFERENCES Persone (CF)
ON UPDATE CASCADE 
);

DROP TABLE IF EXISTS StoricoOrdine;
CREATE TABLE StoricoOrdine(
NROrdine integer (5) primary key,
Targa varchar (7) REFERENCES Veicolo(Targa),
Meccanico smallint (2) REFERENCES Dipendente(Matricola) ON UPDATE NO ACTION,
DataInizioLavori date not null,
DataFineLavori date,
Manodopera smallint default 0,
Preventivo integer default 0,
CostoFinale smallint default 0
);

DROP TABLE IF EXISTS Fornitore;
CREATE TABLE Fornitore(
NomeFornitore char (20),
Contatti varchar(15) not null,
PRIMARY KEY (NomeFornitore)
);

DROP TABLE IF EXISTS Catalogo;
CREATE TABLE Catalogo(
CodicePezzo varchar (4),
VersionePezzo smallint (3), 
Categoria char (50) not null,
Pezzo char (70) not null,
Marca char (15) not null,
Modello varchar (15) not null,
Versione varchar (100) not null,
Prezzo integer (6) not null,
Fornitore char (20),
FOREIGN KEY (Fornitore) REFERENCES Fornitore(NomeFornitore) ON UPDATE CASCADE ,
PRIMARY KEY (CodicePezzo,VersionePezzo)
);

DROP TABLE IF EXISTS PezziNecessari;
CREATE TABLE PezziNecessari(
NROrdine integer (5),
CodicePezzo varchar (4),
Pezzo char (70) not null,
QuantitaNecessaria smallint (2),
QuantitaDisponibile smallint (2),
Prezzo integer (6),
Richiesto date not null,
PRIMARY KEY (NROrdine,CodicePezzo),
FOREIGN KEY (CodicePezzo) REFERENCES Catalogo(CodicePezzo) ON UPDATE CASCADE,
FOREIGN KEY (NROrdine) REFERENCES StoricoOrdine(NROrdine) ON UPDATE NO ACTION 
);

DROP TABLE IF EXISTS OrdinePendente;
CREATE TABLE OrdinePendente(
CodicePezzo varchar (4) PRIMARY KEY,
Quantita smallint (2),
Fornitore char (20),
FOREIGN KEY (CodicePezzo) REFERENCES PezziNecessari(CodicePezzo) ON UPDATE CASCADE 
);

DROP TABLE IF EXISTS Decisione;
CREATE TABLE Decisione(
NROrdine integer (5) primary key,
Risultato ENUM('Positivo','Negativo')  not null,
FOREIGN KEY (NROrdine) REFERENCES StoricoOrdine(NROrdine) ON UPDATE NO ACTION 

);

SET FOREIGN_KEY_CHECKS=1;

------------------------------------------------------------------------------
/*Funzioni*/
DROP FUNCTION IF EXISTS StatoOrdine;
DELIMITER $$
CREATE FUNCTION StatoOrdine( Ordine integer (5) )
RETURNS VARCHAR(30)
BEGIN
DECLARE Stato VARCHAR(30);

IF (SELECT COUNT(*) FROM PezziNecessari WHERE NROrdine=Ordine) = 0
then
SET Stato='ACCETTAZIONE';
RETURN Stato;
ELSEIF (select Risultato from Decisione where NROrdine=Ordine) = 'Negativo'
then 
SET Stato='PREVENTIVO NON ACCETTATO';
RETURN Stato;

ELSEIF (select SUM(QuantitaNecessaria) from PezziNecessari where NROrdine=Ordine) 
		<>
	   (select SUM(QuantitaDisponibile) from PezziNecessari where NROrdine=Ordine)
then 
SET Stato='IN ATTESA PEZZI';
RETURN Stato;

ELSEIF (select CostoFInale from StoricoOrdine where NROrdine=Ordine) = 0
then 
SET Stato='IN LAVORAZIONE';
RETURN Stato;

ELSE
SET Stato='CONCLUSO';
RETURN Stato;
END IF;
END ;$$
DELIMITER ;

DROP FUNCTION IF EXISTS Saldo;
DELIMITER $$
CREATE FUNCTION Saldo()
RETURNS integer (30)
BEGIN
	DECLARE SituazioneEconomica integer(30);
	DECLARE PercentualePezzi integer(10);
	DECLARE OreMensili integer(10);
	SET PercentualePezzi = ((select SUM(Preventivo) from StoricoOrdine WHERE Manodopera <> 0)/100)*10 ;
	SET OreMensili = (select SUM(Manodopera) from StoricoOrdine)*25 ;

	SET SituazioneEconomica = PercentualePezzi + OreMensili;
	RETURN SituazioneEconomica; 
END ;$$
DELIMITER ;

DROP FUNCTION IF EXISTS Ricevuti;
DELIMITER $$
CREATE FUNCTION Ricevuti(Arrivi smallint (2), Pezzo varchar (4))
RETURNS smallint (2)
BEGIN
DECLARE Quantita_Rimanente smallint (2);
DECLARE Quantita_Precedente smallint (2);
SET Quantita_Precedente = (select Quantita from OrdinePendente where CodicePezzo = Pezzo);
SET Quantita_Rimanente = Quantita_Precedente - Arrivi;
if Quantita_Rimanente < 0
then 
	return Quantita_Precedente;
elseif Quantita_Rimanente > 0 
then
	return Quantita_Rimanente;
else
return 0;
end if;
END ;$$
DELIMITER ;

DROP FUNCTION IF EXISTS limite;
DELIMITER $$
CREATE FUNCTION limite(Pezzo varchar (4),Arrivi smallint (2))
RETURNS smallint (2)
BEGIN
	declare PRIOR smallint;
	set PRIOR = (select count(*) from PezziNecessari where CodicePezzo=Pezzo AND QuantitaDisponibile);
	WHILE(
		select SUM(A.QuantitaDisponibile)
		from (
			select CodicePezzo,QuantitaDisponibile
			from PezziNecessari
			where CodicePezzo=Pezzo AND QuantitaDisponibile <> 0
	  		ORDER BY Richiesto DESC
	  		LIMIT PRIOR
	  		) A
		 ) <> Arrivi AND PRIOR >0
	DO
	set PRIOR=PRIOR-1;
	end while;

RETURN PRIOR;
END ;$$
DELIMITER ;

DROP PROCEDURE IF EXISTS Assegnazioni;
DELIMITER $$
CREATE PROCEDURE Assegnazioni (IN Arrivi smallint,IN Pezzo varchar (4))
Begin
DECLARE PRIOR smallint (2);
SET PRIOR = (select limite(Pezzo,Arrivi));
SELECT NROrdine, QuantitaDisponibile AS  Quantita FROM PezziNecessari
WHERE CodicePezzo = Pezzo AND QuantitaDisponibile <> 0
ORDER BY Richiesto DESC
LIMIT PRIOR;
END ;$$
DELIMITER ;

DROP FUNCTION IF EXISTS prossimo;
DELIMITER $$
CREATE FUNCTION prossimo()
RETURNS smallint (2)
BEGIN
DECLARE prossimo smallint;
SET prossimo = (select Max(NROrdine) from StoricoOrdine);
if prossimo IS NULL
then set prossimo = 1;
else set prossimo = prossimo +1;
end if;
return prossimo;
END ;$$
DELIMITER ;

DROP FUNCTION IF EXISTS Meccanico;
DELIMITER $$
CREATE FUNCTION Meccanico()
RETURNS smallint (2)
BEGIN
DECLARE candidato smallint (2);
set candidato = (select Matricola from Dipendente where Mansione = 'Meccanico' and Matricola NOT IN 
									(SELECT Meccanico from StoricoOrdine where Manodopera = 0) LIMIT 1);
	if candidato IS NULL
	then set candidato = (select A.Meccanico 
							from (select Meccanico, SUM(Manodopera) AS OreTotali from StoricoOrdine group by Meccanico) as A 
						where A.OreTotali = 
						(select MIN(A.OreTotali) 
							from (select SUM(Manodopera) AS OreTotali from StoricoOrdine group by Meccanico) AS A)
						 LIMIT 1);
	end if;
return candidato;
END ;$$
DELIMITER ;

----------------------------------------------------------------------------------------

/*TRIGGER*/
delimiter $$
create trigger CalcoloPreventivo
after insert on PezziNecessari
	for each row
begin 
	update StoricoOrdine
	set Preventivo=Preventivo+new.Prezzo*new.QuantitaNecessaria
	where NROrdine=new.NROrdine;
end; $$
delimiter ;

delimiter $$
create trigger AccettazionePreventivo
after insert on StoricoOrdine
	for each row
begin 
	INSERT INTO Decisione values (new.NROrdine,'Negativo');
end; $$
delimiter ;

delimiter $$
create trigger CompatibilitàPezzo
before insert on PezziNecessari
	for each row
begin 

if (select A.Marca
	from(
			select V.Marca,V.Modello,V.Versione
			from Veicolo V join StoricoOrdine S ON (V.Targa=S.Targa)
			where S.NROrdine=New.NROrdine
		) A join
		(
			select C.Marca,C.Modello,C.Versione 
			from Catalogo C
			where NEW.CodicePezzo=C.CodicePezzo	
		) B
	where A.Marca=B.Marca AND A.Modello=B.Modello AND A.Versione=B.Versione) IS NULL
	then SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO=30001, MESSAGE_TEXT='PEZZO INCOMPATIBILE';
	end if;
end; $$
delimiter ;

delimiter $$
create trigger CompatibilitàVeicolo
before insert on Veicolo
	for each row
begin 

if (	select C.Marca
		from Catalogo C
		where NEW.Marca=C.Marca AND NEW.Modello=C.Modello AND NEW.Versione=C.Versione 
		GROUP BY C.Marca) IS NULL
	then SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO=30001, MESSAGE_TEXT='VEICOLO NON DISPONIBILE';
	end if;
end; $$
delimiter ;

delimiter $$
create trigger CostoFinale
before update on StoricoOrdine
	for each row
begin
	if new.Manodopera <> 0
	then 
	set new.CostoFinale = new.Manodopera*25+ new.Preventivo*1.1;
	set new.DataFineLavori=CURDATE();
	end if;
end; $$
delimiter ;

delimiter $$
create trigger Ordinazioni
after update on Decisione
for each row
begin
if new.Risultato = 'Positivo'
then if (select A.CodicePezzo from(
select P.CodicePezzo, P.QuantitaNecessaria, C.Fornitore 
from PezziNecessari P join (
select CodicePezzo,Fornitore 
from Catalogo 
group by CodicePezzo) C
where P.CodicePezzo=C.CodicePezzo AND P.NROrdine=new.NROrdine) A
where A.CodicePezzo IN (select CodicePezzo from OrdinePendente)
LIMIT 1  ) IS NOT NULL
then DROP TEMPORARY TABLE IF EXISTS Nuovi_Pezzi;
CREATE TEMPORARY TABLE Nuovi_Pezzi (CodicePezzo varchar (4),QuantitaNecessaria smallint (2));
INSERT INTO Nuovi_Pezzi (CodicePezzo,QuantitaNecessaria)
select A.CodicePezzo,A.QuantitaNecessaria
from( select P.CodicePezzo, P.QuantitaNecessaria, C.Fornitore 
from PezziNecessari P join (
select CodicePezzo,Fornitore 
from Catalogo 
group by CodicePezzo) C
where P.CodicePezzo=C.CodicePezzo AND P.NROrdine=new.NROrdine) A
where A.CodicePezzo IN (select CodicePezzo from OrdinePendente);
UPDATE OrdinePendente INNER JOIN Nuovi_Pezzi ON OrdinePendente.CodicePezzo=Nuovi_Pezzi.CodicePezzo
SET OrdinePendente.Quantita = OrdinePendente.Quantita + Nuovi_Pezzi.QuantitaNecessaria;
end if;
if  ( select A.CodicePezzo from(
select P.CodicePezzo, P.QuantitaNecessaria, C.Fornitore 
from PezziNecessari P join (
select CodicePezzo,Fornitore 
from Catalogo 
group by CodicePezzo) C
where P.CodicePezzo=C.CodicePezzo AND P.NROrdine=new.NROrdine) A
where A.CodicePezzo NOT IN (select CodicePezzo from OrdinePendente)
LIMIT 1  ) IS NOT NULL
then INSERT INTO OrdinePendente (CodicePezzo,Quantita,Fornitore)
select A.CodicePezzo,A.QuantitaNecessaria,A.Fornitore
from( select P.CodicePezzo, P.QuantitaNecessaria, C.Fornitore 
from PezziNecessari P join (
select CodicePezzo,Fornitore 
from Catalogo 
group by CodicePezzo ) C
where P.CodicePezzo=C.CodicePezzo AND P.NROrdine=new.NROrdine ) A
where A.CodicePezzo NOT IN (select CodicePezzo from OrdinePendente );
end if;
end if;
end; $$ 
delimiter ;

delimiter $$
create trigger AssegnazioneNuoviPezzi
before update on OrdinePendente
	for each row
begin 
	declare PRIOR smallint;
	declare ARRIVATI smallint;

	if new.Quantita < old.Quantita
	then
	set PRIOR = (select count(*) from PezziNecessari where CodicePezzo=new.CodicePezzo);
	set ARRIVATI = old.Quantita-new.Quantita;
	WHILE(
		select SUM(A.QuantitaNecessaria)
		from (
			select CodicePezzo,QuantitaNecessaria
			from PezziNecessari
			where CodicePezzo=new.CodicePezzo AND QuantitaDisponibile=0
	  		ORDER BY Richiesto
	  		LIMIT PRIOR
	  		) A
		 ) <> ARRIVATI AND PRIOR >0
	DO
	set PRIOR=PRIOR-1;
	end while;

	if PRIOR > 0 
	then
		update PezziNecessari
		SET QuantitaDisponibile=QuantitaNecessaria
		where CodicePezzo=new.CodicePezzo AND QuantitaDisponibile=0
		ORDER BY Richiesto
		LIMIT PRIOR ;
	else 
		SET new.Quantita=old.Quantita;
	end if;
end if;
end; $$
delimiter ;

delimiter $$
create trigger Ordine_Completo
after insert on Veicolo
	for each row
begin
	delete from OrdinePendente
		where Quantita=0;
end; $$
delimiter ;

-----------------------------------------------------------------------------------------------------

/*Popolamento Persone*/
INSERT INTO Persone VALUES ("VWUMWZ36P27X669T","GIUSEPPE","MUSSO","axiqehilla-9790@yopmail.com",3195980647);
INSERT INTO Persone VALUES ("VSFKLW45R24M153J","MARIA","CERRATO","kibesussa-1777@yopmail.com",3561920474);
INSERT INTO Persone VALUES ("ANYKZZ79N27M476H","ANDREA","FERRERO","ayoub.ondam@c.nut.emailfake.nut.cc",3109537967);
INSERT INTO Persone VALUES ("OAEZKJ87U08K580Q","MARCO","VIARENGO","ayoub.ondam@c.nut.emailfake.nut.cc",3779921957);
INSERT INTO Persone VALUES ("BWJRRC34D17X910B","FRANCESCO","FASSIO","ammuhamil-8809@yopmail.com",3339491161);
INSERT INTO Persone VALUES ("GHOXHL33M22B430A","ALESSANDRO","GALLO","vimannyhap-0118@yopmail.com",3269146401);
INSERT INTO Persone VALUES ("IQDOCS97P08I934D","GIOVANNI","ROSSO","jajisudaf-7503@yopmail.com",3866023156);
INSERT INTO Persone VALUES ("JHMYAE65Y02D977F","ROBERTO","BIANCO","bafuzadderr-9628@yopmail.com",3996455585);
INSERT INTO Persone VALUES ("YUQAMA57R27D159Q","LUCA","RAVIOLA","befudadatto-1365@yopmail.com",3658781562);
INSERT INTO Persone VALUES ("OXTKDM06K19U272E","ANTONIO","CONTI","ahadudig-6616@yopmail.com",3982722987);
INSERT INTO Persone VALUES ("GXDQHN91U07Q793M","FRANCESCA","SEFEROVIC","saxebise-1254@yopmail.com",3692574572);
INSERT INTO Persone VALUES ("OJQPSR82J15L722Q","ANNA","AMERIO","mogiqacy-8992@yopmail.com",3177386812);
INSERT INTO Persone VALUES ("IYCZNE80F09T729J","PAOLO","TORCHIO","avokinni-2074@yopmail.com",3089031469);
INSERT INTO Persone VALUES ("RLNESS12O17U896Y","MARIO","NEGRO","diwizobaz-6209@yopmail.com",3200788035);
INSERT INTO Persone VALUES ("ZRAIBK26Z12S151B","LUIGI","MARINO","xiladdore-7048@yopmail.com",3357115755);
INSERT INTO Persone VALUES ("KXYRUH41E02F397D","DAVIDE","GRASSO","jappebequmm-3300@yopmail.com",3894937492);
INSERT INTO Persone VALUES ("CCQYKA10R06J330O","MATTEO","GRAZIANO","offikocof-7853@yopmail.com",3465483559);
INSERT INTO Persone VALUES ("YRFJPN34V12X920N","GIULIA","BARBERO","nipatyfa-5144@yopmail.com",3539996110);
INSERT INTO Persone VALUES ("MROFYK58F27O229C","FABIO","GAMBA","timiwennara-1789@yopmail.com",3334635634);
INSERT INTO Persone VALUES ("MCZDCO85C03Q217D","PAOLA","NOSENZO","middafebi-3802@yopmail.com",3752725983);
INSERT INTO Persone VALUES ("MRIASG95R06P914H","SALVATORE","BINELLO","ahadudig-6616@yopmail.com",3902557366);
INSERT INTO Persone VALUES ("QMWNBK33H24S878E","GIUSEPPINA","PALUMBO","saxebise-1254@yopmail.com",3368548893);
INSERT INTO Persone VALUES ("RDUXKE14H00K011H","STEFANO","PENNA","mogiqacy-8992@yopmail.com",3532583883);
INSERT INTO Persone VALUES ("XLLURO99M23L836A","LORENZO","FERRARIS","avokinni-2074@yopmail.com",3596092091);
INSERT INTO Persone VALUES ("CDKKRV91H11T832T","DANIELA","RISSONE","diwizobaz-6209@yopmail.com",3396808826);
INSERT INTO Persone VALUES ("FZBUQE87O02H965V","ELENA","FRANCO","xiladdore-7048@yopmail.com",3176441388);
INSERT INTO Persone VALUES ("KUFOBO63T06N728A","ROSA","MARELLO","jappebequmm-3300@yopmail.com",3272110449);
INSERT INTO Persone VALUES ("PPBRDZ32P05C163U","MASSIMO","NEBIOLO","offikocof-7853@yopmail.com",3969021174);
INSERT INTO Persone VALUES ("TYPMTA81X14G615W","ANGELA","PEROSINO","nipatyfa-5144@yopmail.com",3126453040);
INSERT INTO Persone VALUES ("HJFLIY01Q17X879X","GIORGIO","RUSSO","timiwennara-1789@yopmail.com",3038814137);
INSERT INTO Persone VALUES ("BAJRWN85U25K602S","ANNA MARIA","BRUNO","middafebi-3802@yopmail.com",3053888945);
INSERT INTO Persone VALUES ("ZTIRAD47F14K171Z","LAURA","MONTICONE","ahadudig-6616@yopmail.com",3716422280);
INSERT INTO Persone VALUES ("KEPDIG32U22G997Y","CHIARA","MORRA","saxebise-1254@yopmail.com",3235046624);
INSERT INTO Persone VALUES ("YTVWYW99L07N082X","SARA","CARBONE","mogiqacy-8992@yopmail.com",3690644506);
INSERT INTO Persone VALUES ("ROXFOV83O04A922A","ALBERTO","PAVESE","avokinni-2074@yopmail.com",3947046550);


/*popolamento meccanici*/
INSERT INTO Dipendente VALUES (1,"GHOXHL33M22B430A","Meccanico");
INSERT INTO Dipendente VALUES (2,"ZRAIBK26Z12S151B","Meccanico");
INSERT INTO Dipendente VALUES (3,"YRFJPN34V12X920N","Meccanico");
INSERT INTO Dipendente VALUES (4,"QMWNBK33H24S878E","Meccanico");

/*popolamento segretario*/
INSERT INTO Dipendente VALUES (5,"TYPMTA81X14G615W","Segretario");

/*popolamento fornitori*/
INSERT INTO Fornitore VALUES ("ROSI STAR",3906266453);
INSERT INTO Fornitore VALUES ("RAEM s.r.l",3582609708);
INSERT INTO Fornitore VALUES ("ARBO s.r.l",3633958721);
INSERT INTO Fornitore VALUES ("AUTOCAR LAGUNA",3097638835);

/*popolamento catalogo*/
INSERT INTO Catalogo VALUES (1,1,"Guarnizioni","Kit Riparazione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (2,1,"Guarnizioni","Pomello del Cambio e Componenti","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (3,1,"Preparazione carburante","Guarnizioni","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (4,1,"Preparazione carburante","Kit riparazione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (5,1,"Raffreddamento","Pompa Acqua","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (6,1,"Raffreddamento","Radiatore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (7,1,"Raffreddamento","Radiatore Riscaldamento","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (8,1,"Raffreddamento","Sensori e Interruttori","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (9,1,"Raffreddamento","Termostato","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (10,1,"Raffreddamento","Tubo Radiatore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (11,1,"Raffreddamento","Vaschetta Radiatore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (12,1,"Riscaldamento / Aerazion","Radiatore Riscaldamento","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (13,1,"Sistema chiusura","Serratura","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (14,1,"Sistema chiusura","Serrature Abitacolo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",47,"ROSI STAR");
INSERT INTO Catalogo VALUES (15,1,"Sistema frenante","Accessori / Componenti","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (16,1,"Sistema frenante","Cavo Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (17,1,"Sistema frenante","Cilindretto Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (18,1,"Sistema frenante","Cilindro Freno Ruota","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (19,1,"Sistema frenante","Correttore Frenata","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (20,1,"Sistema frenante","Dischi Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (21,1,"Sistema frenante","Freno a Tamburo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (22,1,"Sistema frenante","Ganasce Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (23,1,"Sistema frenante","Interruttore Stop","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (24,1,"Sistema frenante","Kit Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (25,1,"Sistema frenante","Olio Freni","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (26,1,"Sistema frenante","Pastiglie Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (27,1,"Sistema frenante","Pinza Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (28,1,"Sistema frenante","Pompa Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (29,1,"Sistema frenante","Supporto Pinza Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (30,1,"Sistema frenante","Tubi Freno","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (31,1,"Sistemi per il comfort ","Alzacristalli","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (32,1,"Sospensione / Ammortizzazione","Ammortizzatori","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (33,1,"Sospensione / Ammortizzazione","Kit Sospensioni","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (34,1,"Sospensione / Ammortizzazione","Molla Ammortizzatore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (35,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (36,1,"Sospensione / Ammortizzazione","Biellette Barra Stabilizzatrice","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (37,1,"Sospensione / Ammortizzazione","Braccio Oscillante","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (38,1,"Sospensione / Ammortizzazione","Cuscinetto Ruota","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (39,1,"Sospensione / Ammortizzazione","Fuso Dell'asse","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (40,1,"Sospensione / Ammortizzazione","Gommini Barra Stabilizzatrice","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (41,1,"Sospensione / Ammortizzazione","Mozzo Ruota","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (42,1,"Sospensione / Ammortizzazione","Silent Block","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",34,"ROSI STAR");
INSERT INTO Catalogo VALUES (43,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (44,1,"Sospensione / Ammortizzazione","Supporto Assale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (45,1,"Sospensione / Ammortizzazione","Testina Braccio Oscillante","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (46,1,"Sterzo","Cuffia Scatola Sterzo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",34,"ROSI STAR");
INSERT INTO Catalogo VALUES (47,1,"Sterzo","Filtro Idraulico Sterzo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (48,1,"Sterzo","Servosterzo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (49,1,"Sterzo","Snodo Assiale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (50,1,"Sterzo","Testina dello Sterzo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (51,1,"Sterzo","Tirante Sterzo","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (52,1,"Tergicristalli","Tergicristalli","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (53,1,"Equipaggiamento interno","Accessori","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (54,1,"Equipaggiamento interno","Alzacristalli","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (55,1,"Equipaggiamento interno","Leveraggio Manuale / a Pedale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (56,1,"Equipaggiamento interno","Vano Bagagli / di Carico","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (57,1,"Trasmissione a cinghia","Cinghia Trapezoidale.M","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (58,1,"Trasmissione a cinghia","Pompa Acqua + Kit Cinghia Distribuzione.M","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (59,1,"Trasmissione a cinghia","Rullo Tendicinghia.M","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (60,1,"Trasmissione finale","Kit Giunto Omocinetico","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (61,1,"Trasmissione finale","Parti di Fissaggio/Accessori","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (62,1,"Trasmissione finale","Semiasse","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (63,1,"Trasmissione finale","Soffietto","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (64,1,"Trasmissione finale","Tripode","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (65,1,"Filtro","Filtro Aria","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (66,1,"Filtro","Filtro Carburante","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (67,1,"Filtro","Filtro Idraulico","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (68,1,"Filtro","Filtro Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (69,1,"Frizione / parti di montaggio","Cavo Frizione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (70,1,"Frizione / parti di montaggio","Disco Frizione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (71,1,"Frizione / parti di montaggio","Dispositivo Disinnesto Centrale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (72,1,"Frizione / parti di montaggio","Kit Frizione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (73,1,"Frizione / parti di montaggio","Pedali e Copripedale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (74,1,"Frizione / parti di montaggio","Pompa Frizione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (75,1,"Frizione / parti di montaggio","Spingidisco","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (76,1,"Frizione / parti di montaggio","Сuscinetto Reggispinta","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (77,1,"impianto alimentazione carburante","Filtro Carburante","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (78,1,"impianto alimentazione carburante","Pompa Carburante","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (79,1,"Impianto di accensione","Bobina","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (80,1,"Impianto di accensione","Candele","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (81,1,"Impianto di accensione","Cavi Candele","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",34,"ROSI STAR");
INSERT INTO Catalogo VALUES (82,1,"Impianto di accensione","Spinterogeno e Componenti","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (83,1,"Impianto elettrico","Alternatore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (84,1,"Impianto elettrico","Alternatore Componenti","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (85,1,"Impianto elettrico","Batteria","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (86,1,"Impianto elettrico","Cavo Tachimetro","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (87,1,"Impianto elettrico","Elettromagnete Motorino Avviamento","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (88,1,"Impianto elettrico","Fari","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (89,1,"Impianto elettrico","Frecce","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (90,1,"Impianto elettrico","Interruttore / Regolatore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",47,"ROSI STAR");
INSERT INTO Catalogo VALUES (91,1,"Impianto elettrico","Lampadina Faro Principale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (92,1,"Impianto elettrico","Lampadina Freccia","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (93,1,"Impianto elettrico","Lampadina Luce Posteriore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (94,1,"Impianto elettrico","Lampadina Luce Targa","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (95,1,"Impianto elettrico","Motorino D'avviamento","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (96,1,"Impianto elettrico","Regolatore di Tensione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (97,1,"Impianto elettrico","Relè","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (98,1,"Impianto elettrico","Relè Frecce","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (99,1,"Impianto gas scarico","Guarnizione Tubo Gas Scarico","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (100,1,"Impianto gas scarico","Manicotto saldatura","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (101,1,"Impianto gas scarico","Marmitta","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (102,1,"Impianto gas scarico","Morsetto","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (103,1,"Impianto gas scarico","Nastro di Gomma","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (104,1,"Impianto gas scarico","Pezzo per Bloccaggio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (105,1,"Impianto gas scarico","Staffa","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (106,1,"Impianto gas scarico","Supporto","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (107,1,"Impianto gas scarico","Tampone in Gomma","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (108,1,"Impianto gas scarico","Tubi Gas Scarico","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",47,"ROSI STAR");
INSERT INTO Catalogo VALUES (109,1,"Motore","Albero a Canne","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (110,1,"Motore","Asta Livello Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (111,1,"Motore","Bronzina Piede di Biella","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (112,1,"Motore","Bronzine Motore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (113,1,"Motore","Bulbo Pressione Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (114,1,"Motore","Bulloni Testata","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (115,1,"Motore","Cilindro / Pistone","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (116,1,"Motore","Cinghia Distribuzione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (117,1,"Motore","Cinghia Trapezoidale","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (118,1,"Motore","Comando valvole","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (119,1,"Motore","Coperchio Punterie","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (120,1,"Motore","Fasce Elastiche","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (121,1,"Motore","Filtro Aria","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (122,1,"Motore","Filtro Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (123,1,"Motore","Gommini Valvole","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (124,1,"Motore","Guarnizione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (125,1,"Motore","Guarnizione testata","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (126,1,"Motore","Guarnizione Carter","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (127,1,"Motore","Guarnizione Collettore Aspirazione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (128,1,"Motore","Guarnizione Collettore Scarico","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (129,1,"Motore","Guarnizione Coperchio Punterie","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (130,1,"Motore","Guarnizione Coppa Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (131,1,"Motore","Guarnizione Tenuta Circuito Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (132,1,"Motore","Guarnizione Testata","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (133,1,"Motore","Guida / Guarnizione / Regolazione Valvole","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (134,1,"Motore","Impianto Elettrico Motore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (135,1,"Motore","Kit Cinghia Distribuzione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (136,1,"Motore","Kit Completo di Guarnizioni","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (137,1,"Motore","Paraolio Albero A Camme","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (138,1,"Motore","Paraolio Albero Motore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (139,1,"Motore","Paraolio Albero a Camme","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (140,1,"Motore","Pistone","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (141,1,"Motore","Pompa Acqua + Kit Cinghia Distribuzione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (142,1,"Motore","Pulegge Albero a Gomiti","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (143,1,"Motore","Punterie","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (144,1,"Motore","Rullo Tendicinghia","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (145,1,"Motore","Semicuscinetto Albero a Gomiti","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (146,1,"Motore","Supporto Motore","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (147,1,"Motore","Tappo Coppa Olio e Guarnizione Tappo Coppa Olio","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (148,1,"Motore","Tappo Monoblocco","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (149,1,"Motore","Valvola di Scarico e Valvola Aspirazione","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (1,2,"Guarnizioni","Kit Riparazione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (2,2,"Guarnizioni","Pomello del Cambio e Componenti","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (3,2,"Preparazione carburante","Guarnizioni","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (4,2,"Preparazione carburante","Kit riparazione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (5,2,"Raffreddamento","Pompa Acqua","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (6,2,"Raffreddamento","Radiatore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (7,2,"Raffreddamento","Radiatore Riscaldamento","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (8,2,"Raffreddamento","Sensori e Interruttori","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (9,2,"Raffreddamento","Termostato","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (10,2,"Raffreddamento","Tubo Radiatore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (11,2,"Raffreddamento","Vaschetta Radiatore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (12,2,"Riscaldamento / Aerazion","Radiatore Riscaldamento","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (13,2,"Sistema chiusura","Serratura","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (14,2,"Sistema chiusura","Serrature Abitacolo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",47,"ROSI STAR");
INSERT INTO Catalogo VALUES (15,2,"Sistema frenante","Accessori / Componenti","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (16,2,"Sistema frenante","Cavo Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (17,2,"Sistema frenante","Cilindretto Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (18,2,"Sistema frenante","Cilindro Freno Ruota","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (19,2,"Sistema frenante","Correttore Frenata","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (20,2,"Sistema frenante","Dischi Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (21,2,"Sistema frenante","Freno a Tamburo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (22,2,"Sistema frenante","Ganasce Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (23,2,"Sistema frenante","Interruttore Stop","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (24,2,"Sistema frenante","Kit Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (25,2,"Sistema frenante","Olio Freni","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (26,2,"Sistema frenante","Pastiglie Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (27,2,"Sistema frenante","Pinza Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (28,2,"Sistema frenante","Pompa Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (29,2,"Sistema frenante","Supporto Pinza Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (30,2,"Sistema frenante","Tubi Freno","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (31,2,"Sistemi per il comfort ","Alzacristalli","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (32,2,"Sospensione / Ammortizzazione","Ammortizzatori","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (33,2,"Sospensione / Ammortizzazione","Kit Sospensioni","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (34,2,"Sospensione / Ammortizzazione","Molla Ammortizzatore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (35,2,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (36,2,"Sospensione / Ammortizzazione","Biellette Barra Stabilizzatrice","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (37,2,"Sospensione / Ammortizzazione","Braccio Oscillante","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (38,2,"Sospensione / Ammortizzazione","Cuscinetto Ruota","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (39,2,"Sospensione / Ammortizzazione","Fuso Dell'asse","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (40,2,"Sospensione / Ammortizzazione","Gommini Barra Stabilizzatrice","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (41,2,"Sospensione / Ammortizzazione","Mozzo Ruota","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (42,2,"Sospensione / Ammortizzazione","Silent Block","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",34,"ROSI STAR");
INSERT INTO Catalogo VALUES (43,2,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (44,2,"Sospensione / Ammortizzazione","Supporto Assale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (45,2,"Sospensione / Ammortizzazione","Testina Braccio Oscillante","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (46,2,"Sterzo","Cuffia Scatola Sterzo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",34,"ROSI STAR");
INSERT INTO Catalogo VALUES (47,2,"Sterzo","Filtro Idraulico Sterzo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (48,2,"Sterzo","Servosterzo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (49,2,"Sterzo","Snodo Assiale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (50,2,"Sterzo","Testina dello Sterzo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (51,2,"Sterzo","Tirante Sterzo","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (52,2,"Tergicristalli","Tergicristalli","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (53,2,"Equipaggiamento interno","Accessori","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (54,2,"Equipaggiamento interno","Alzacristalli","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (55,2,"Equipaggiamento interno","Leveraggio Manuale / a Pedale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",40,"ROSI STAR");
INSERT INTO Catalogo VALUES (56,2,"Equipaggiamento interno","Vano Bagagli / di Carico","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (57,2,"Trasmissione a cinghia","Cinghia Trapezoidale.M","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (58,2,"Trasmissione a cinghia","Pompa Acqua + Kit Cinghia Distribuzione.M","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (59,2,"Trasmissione a cinghia","Rullo Tendicinghia.M","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",45,"ROSI STAR");
INSERT INTO Catalogo VALUES (60,2,"Trasmissione finale","Kit Giunto Omocinetico","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (61,2,"Trasmissione finale","Parti di Fissaggio/Accessori","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (62,2,"Trasmissione finale","Semiasse","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (63,2,"Trasmissione finale","Soffietto","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (64,2,"Trasmissione finale","Tripode","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (65,2,"Filtro","Filtro Aria","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (66,2,"Filtro","Filtro Carburante","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (67,2,"Filtro","Filtro Idraulico","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (68,2,"Filtro","Filtro Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (69,2,"Frizione / parti di montaggio","Cavo Frizione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (70,2,"Frizione / parti di montaggio","Disco Frizione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (71,2,"Frizione / parti di montaggio","Dispositivo Disinnesto Centrale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (72,2,"Frizione / parti di montaggio","Kit Frizione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (73,2,"Frizione / parti di montaggio","Pedali e Copripedale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (74,2,"Frizione / parti di montaggio","Pompa Frizione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (75,2,"Frizione / parti di montaggio","Spingidisco","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (76,2,"Frizione / parti di montaggio","Сuscinetto Reggispinta","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (77,2,"impianto alimentazione carburante","Filtro Carburante","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (78,2,"impianto alimentazione carburante","Pompa Carburante","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (79,2,"Impianto di accensione","Bobina","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (80,2,"Impianto di accensione","Candele","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (81,2,"Impianto di accensione","Cavi Candele","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",34,"ROSI STAR");
INSERT INTO Catalogo VALUES (82,2,"Impianto di accensione","Spinterogeno e Componenti","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (83,2,"Impianto elettrico","Alternatore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (84,2,"Impianto elettrico","Alternatore Componenti","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (85,2,"Impianto elettrico","Batteria","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (86,2,"Impianto elettrico","Cavo Tachimetro","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (87,2,"Impianto elettrico","Elettromagnete Motorino Avviamento","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (88,2,"Impianto elettrico","Fari","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (89,2,"Impianto elettrico","Frecce","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (90,2,"Impianto elettrico","Interruttore / Regolatore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",47,"ROSI STAR");
INSERT INTO Catalogo VALUES (91,2,"Impianto elettrico","Lampadina Faro Principale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (92,2,"Impianto elettrico","Lampadina Freccia","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (93,2,"Impianto elettrico","Lampadina Luce Posteriore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (94,2,"Impianto elettrico","Lampadina Luce Targa","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (95,2,"Impianto elettrico","Motorino D'avviamento","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (96,2,"Impianto elettrico","Regolatore di Tensione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (97,2,"Impianto elettrico","Relè","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (98,2,"Impianto elettrico","Relè Frecce","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (99,2,"Impianto gas scarico","Guarnizione Tubo Gas Scarico","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (100,2,"Impianto gas scarico","Manicotto saldatura","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (101,2,"Impianto gas scarico","Marmitta","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (102,2,"Impianto gas scarico","Morsetto","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",43,"ROSI STAR");
INSERT INTO Catalogo VALUES (103,2,"Impianto gas scarico","Nastro di Gomma","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (104,2,"Impianto gas scarico","Pezzo per Bloccaggio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",31,"ROSI STAR");
INSERT INTO Catalogo VALUES (105,2,"Impianto gas scarico","Staffa","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (106,2,"Impianto gas scarico","Supporto","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (107,2,"Impianto gas scarico","Tampone in Gomma","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (108,2,"Impianto gas scarico","Tubi Gas Scarico","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",47,"ROSI STAR");
INSERT INTO Catalogo VALUES (109,2,"Motore","Albero a Canne","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",42,"ROSI STAR");
INSERT INTO Catalogo VALUES (110,2,"Motore","Asta Livello Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (111,2,"Motore","Bronzina Piede di Biella","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (112,2,"Motore","Bronzine Motore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (113,2,"Motore","Bulbo Pressione Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (114,2,"Motore","Bulloni Testata","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (115,2,"Motore","Cilindro / Pistone","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (116,2,"Motore","Cinghia Distribuzione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (117,2,"Motore","Cinghia Trapezoidale","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (118,2,"Motore","Comando valvole","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (119,2,"Motore","Coperchio Punterie","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (120,2,"Motore","Fasce Elastiche","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (121,2,"Motore","Filtro Aria","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (122,2,"Motore","Filtro Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (123,2,"Motore","Gommini Valvole","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (124,2,"Motore","Guarnizione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (125,2,"Motore","Guarnizione testata","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (126,2,"Motore","Guarnizione Carter","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (127,2,"Motore","Guarnizione Collettore Aspirazione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (128,2,"Motore","Guarnizione Collettore Scarico","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (129,2,"Motore","Guarnizione Coperchio Punterie","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",46,"ROSI STAR");
INSERT INTO Catalogo VALUES (130,2,"Motore","Guarnizione Coppa Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (131,2,"Motore","Guarnizione Tenuta Circuito Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (132,2,"Motore","Guarnizione Testata","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (133,2,"Motore","Guida / Guarnizione / Regolazione Valvole","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (134,2,"Motore","Impianto Elettrico Motore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",36,"ROSI STAR");
INSERT INTO Catalogo VALUES (135,2,"Motore","Kit Cinghia Distribuzione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (136,2,"Motore","Kit Completo di Guarnizioni","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (137,2,"Motore","Paraolio Albero A Camme","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",44,"ROSI STAR");
INSERT INTO Catalogo VALUES (138,2,"Motore","Paraolio Albero Motore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (139,2,"Motore","Paraolio Albero a Camme","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",35,"ROSI STAR");
INSERT INTO Catalogo VALUES (140,2,"Motore","Pistone","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",41,"ROSI STAR");
INSERT INTO Catalogo VALUES (141,2,"Motore","Pompa Acqua + Kit Cinghia Distribuzione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",30,"ROSI STAR");
INSERT INTO Catalogo VALUES (142,2,"Motore","Pulegge Albero a Gomiti","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",39,"ROSI STAR");
INSERT INTO Catalogo VALUES (143,2,"Motore","Punterie","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",49,"ROSI STAR");
INSERT INTO Catalogo VALUES (144,2,"Motore","Rullo Tendicinghia","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",38,"ROSI STAR");
INSERT INTO Catalogo VALUES (145,2,"Motore","Semicuscinetto Albero a Gomiti","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",50,"ROSI STAR");
INSERT INTO Catalogo VALUES (146,2,"Motore","Supporto Motore","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",32,"ROSI STAR");
INSERT INTO Catalogo VALUES (147,2,"Motore","Tappo Coppa Olio e Guarnizione Tappo Coppa Olio","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",48,"ROSI STAR");
INSERT INTO Catalogo VALUES (148,2,"Motore","Tappo Monoblocco","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",37,"ROSI STAR");
INSERT INTO Catalogo VALUES (149,2,"Motore","Valvola di Scarico e Valvola Aspirazione","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000",33,"ROSI STAR");
INSERT INTO Catalogo VALUES (150,1,"Guarnizioni","Kit Riparazione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",36,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (151,1,"Guarnizioni","Pomello del Cambio e Componenti","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (152,1,"Preparazione carburante","Guarnizioni","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",45,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (153,1,"Preparazione carburante","Kit riparazione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (154,1,"Raffreddamento","Pompa Acqua","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (155,1,"Raffreddamento","Radiatore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (156,1,"Raffreddamento","Radiatore Riscaldamento","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (157,1,"Raffreddamento","Sensori e Interruttori","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",38,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (158,1,"Raffreddamento","Termostato","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",40,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (159,1,"Raffreddamento","Tubo Radiatore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",43,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (160,1,"Raffreddamento","Vaschetta Radiatore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (161,1,"Riscaldamento / Aerazion","Radiatore Riscaldamento","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (162,1,"Sistema chiusura","Serratura","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (163,1,"Sistema chiusura","Serrature Abitacolo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",47,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (164,1,"Sistema frenante","Accessori / Componenti","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (165,1,"Sistema frenante","Cavo Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (166,1,"Sistema frenante","Cilindretto Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (167,1,"Sistema frenante","Cilindro Freno Ruota","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (168,1,"Sistema frenante","Correttore Frenata","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",40,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (169,1,"Sistema frenante","Dischi Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (170,1,"Sistema frenante","Freno a Tamburo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (171,1,"Sistema frenante","Ganasce Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",43,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (172,1,"Sistema frenante","Interruttore Stop","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (173,1,"Sistema frenante","Kit Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (174,1,"Sistema frenante","Olio Freni","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (175,1,"Sistema frenante","Pastiglie Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (176,1,"Sistema frenante","Pinza Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (177,1,"Sistema frenante","Pompa Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (178,1,"Sistema frenante","Supporto Pinza Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (179,1,"Sistema frenante","Tubi Freno","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",40,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (180,1,"Sistemi per il comfort ","Alzacristalli","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (181,1,"Sospensione / Ammortizzazione","Ammortizzatori","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (182,1,"Sospensione / Ammortizzazione","Kit Sospensioni","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",42,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (183,1,"Sospensione / Ammortizzazione","Molla Ammortizzatore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",45,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (184,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",30,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (185,1,"Sospensione / Ammortizzazione","Biellette Barra Stabilizzatrice","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (186,1,"Sospensione / Ammortizzazione","Braccio Oscillante","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",38,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (187,1,"Sospensione / Ammortizzazione","Cuscinetto Ruota","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",36,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (188,1,"Sospensione / Ammortizzazione","Fuso Dell'asse","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",42,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (189,1,"Sospensione / Ammortizzazione","Gommini Barra Stabilizzatrice","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (190,1,"Sospensione / Ammortizzazione","Mozzo Ruota","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (191,1,"Sospensione / Ammortizzazione","Silent Block","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",34,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (192,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",30,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (193,1,"Sospensione / Ammortizzazione","Supporto Assale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (194,1,"Sospensione / Ammortizzazione","Testina Braccio Oscillante","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",45,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (195,1,"Sterzo","Cuffia Scatola Sterzo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",34,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (196,1,"Sterzo","Filtro Idraulico Sterzo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",42,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (197,1,"Sterzo","Servosterzo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (198,1,"Sterzo","Snodo Assiale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (199,1,"Sterzo","Testina dello Sterzo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (200,1,"Sterzo","Tirante Sterzo","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (201,1,"Tergicristalli","Tergicristalli","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",43,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (202,1,"Equipaggiamento interno","Accessori","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",31,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (203,1,"Equipaggiamento interno","Alzacristalli","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (204,1,"Equipaggiamento interno","Leveraggio Manuale / a Pedale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",40,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (205,1,"Equipaggiamento interno","Vano Bagagli / di Carico","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (206,1,"Trasmissione a cinghia","Cinghia Trapezoidale.M","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (207,1,"Trasmissione a cinghia","Pompa Acqua + Kit Cinghia Distribuzione.M","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (208,1,"Trasmissione a cinghia","Rullo Tendicinghia.M","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",45,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (209,1,"Trasmissione finale","Kit Giunto Omocinetico","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (210,1,"Trasmissione finale","Parti di Fissaggio/Accessori","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (211,1,"Trasmissione finale","Semiasse","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (212,1,"Trasmissione finale","Soffietto","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",36,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (213,1,"Trasmissione finale","Tripode","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (214,1,"Filtro","Filtro Aria","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (215,1,"Filtro","Filtro Carburante","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (216,1,"Filtro","Filtro Idraulico","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (217,1,"Filtro","Filtro Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (218,1,"Frizione / parti di montaggio","Cavo Frizione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (219,1,"Frizione / parti di montaggio","Disco Frizione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",43,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (220,1,"Frizione / parti di montaggio","Dispositivo Disinnesto Centrale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (221,1,"Frizione / parti di montaggio","Kit Frizione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (222,1,"Frizione / parti di montaggio","Pedali e Copripedale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (223,1,"Frizione / parti di montaggio","Pompa Frizione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",31,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (224,1,"Frizione / parti di montaggio","Spingidisco","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (225,1,"Frizione / parti di montaggio","Сuscinetto Reggispinta","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (226,1,"impianto alimentazione carburante","Filtro Carburante","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (227,1,"impianto alimentazione carburante","Pompa Carburante","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (228,1,"Impianto di accensione","Bobina","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",36,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (229,1,"Impianto di accensione","Candele","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (230,1,"Impianto di accensione","Cavi Candele","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",34,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (231,1,"Impianto di accensione","Spinterogeno e Componenti","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",30,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (232,1,"Impianto elettrico","Alternatore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (233,1,"Impianto elettrico","Alternatore Componenti","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (234,1,"Impianto elettrico","Batteria","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",43,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (235,1,"Impianto elettrico","Cavo Tachimetro","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (236,1,"Impianto elettrico","Elettromagnete Motorino Avviamento","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",31,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (237,1,"Impianto elettrico","Fari","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (238,1,"Impianto elettrico","Frecce","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (239,1,"Impianto elettrico","Interruttore / Regolatore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",47,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (240,1,"Impianto elettrico","Lampadina Faro Principale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (241,1,"Impianto elettrico","Lampadina Freccia","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (242,1,"Impianto elettrico","Lampadina Luce Posteriore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (243,1,"Impianto elettrico","Lampadina Luce Targa","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (244,1,"Impianto elettrico","Motorino D'avviamento","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (245,1,"Impianto elettrico","Regolatore di Tensione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",31,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (246,1,"Impianto elettrico","Relè","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",42,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (247,1,"Impianto elettrico","Relè Frecce","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",38,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (248,1,"Impianto gas scarico","Guarnizione Tubo Gas Scarico","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",31,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (249,1,"Impianto gas scarico","Manicotto saldatura","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (250,1,"Impianto gas scarico","Marmitta","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (251,1,"Impianto gas scarico","Morsetto","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",43,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (252,1,"Impianto gas scarico","Nastro di Gomma","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (253,1,"Impianto gas scarico","Pezzo per Bloccaggio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",31,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (254,1,"Impianto gas scarico","Staffa","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (255,1,"Impianto gas scarico","Supporto","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (256,1,"Impianto gas scarico","Tampone in Gomma","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (257,1,"Impianto gas scarico","Tubi Gas Scarico","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",47,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (258,1,"Motore","Albero a Canne","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",42,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (259,1,"Motore","Asta Livello Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",38,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (260,1,"Motore","Bronzina Piede di Biella","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (261,1,"Motore","Bronzine Motore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (262,1,"Motore","Bulbo Pressione Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (263,1,"Motore","Bulloni Testata","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (264,1,"Motore","Cilindro / Pistone","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (265,1,"Motore","Cinghia Distribuzione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",30,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (266,1,"Motore","Cinghia Trapezoidale","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (267,1,"Motore","Comando valvole","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (268,1,"Motore","Coperchio Punterie","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (269,1,"Motore","Fasce Elastiche","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (270,1,"Motore","Filtro Aria","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (271,1,"Motore","Filtro Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (272,1,"Motore","Gommini Valvole","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (273,1,"Motore","Guarnizione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",36,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (274,1,"Motore","Guarnizione testata","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (275,1,"Motore","Guarnizione Carter","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (276,1,"Motore","Guarnizione Collettore Aspirazione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",38,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (277,1,"Motore","Guarnizione Collettore Scarico","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (278,1,"Motore","Guarnizione Coperchio Punterie","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",46,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (279,1,"Motore","Guarnizione Coppa Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (280,1,"Motore","Guarnizione Tenuta Circuito Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",30,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (281,1,"Motore","Guarnizione Testata","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (282,1,"Motore","Guida / Guarnizione / Regolazione Valvole","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (283,1,"Motore","Impianto Elettrico Motore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",36,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (284,1,"Motore","Kit Cinghia Distribuzione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (285,1,"Motore","Kit Completo di Guarnizioni","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (286,1,"Motore","Paraolio Albero A Camme","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",44,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (287,1,"Motore","Paraolio Albero Motore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (288,1,"Motore","Paraolio Albero a Camme","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",35,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (289,1,"Motore","Pistone","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",41,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (290,1,"Motore","Pompa Acqua + Kit Cinghia Distribuzione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",30,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (291,1,"Motore","Pulegge Albero a Gomiti","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",39,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (292,1,"Motore","Punterie","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",49,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (293,1,"Motore","Rullo Tendicinghia","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",38,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (294,1,"Motore","Semicuscinetto Albero a Gomiti","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",50,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (295,1,"Motore","Supporto Motore","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",32,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (296,1,"Motore","Tappo Coppa Olio e Guarnizione Tappo Coppa Olio","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",48,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (297,1,"Motore","Tappo Monoblocco","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",37,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (298,1,"Motore","Valvola di Scarico e Valvola Aspirazione","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)",33,"RAEM s.r.l");
INSERT INTO Catalogo VALUES (299,1,"Guarnizioni","Kit Riparazione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (300,1,"Guarnizioni","Pomello del Cambio e Componenti","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (301,1,"Preparazione carburante","Guarnizioni","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (302,1,"Preparazione carburante","Kit riparazione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (303,1,"Raffreddamento","Pompa Acqua","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (304,1,"Raffreddamento","Radiatore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (305,1,"Raffreddamento","Radiatore Riscaldamento","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (306,1,"Raffreddamento","Sensori e Interruttori","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (307,1,"Raffreddamento","Termostato","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (308,1,"Raffreddamento","Tubo Radiatore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (309,1,"Raffreddamento","Vaschetta Radiatore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (310,1,"Riscaldamento / Aerazion","Radiatore Riscaldamento","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (311,1,"Sistema chiusura","Serratura","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (312,1,"Sistema chiusura","Serrature Abitacolo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (313,1,"Sistema frenante","Accessori / Componenti","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (314,1,"Sistema frenante","Cavo Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (315,1,"Sistema frenante","Cilindretto Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (316,1,"Sistema frenante","Cilindro Freno Ruota","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (317,1,"Sistema frenante","Correttore Frenata","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (318,1,"Sistema frenante","Dischi Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (319,1,"Sistema frenante","Freno a Tamburo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (320,1,"Sistema frenante","Ganasce Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (321,1,"Sistema frenante","Interruttore Stop","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (322,1,"Sistema frenante","Kit Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (323,1,"Sistema frenante","Olio Freni","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (324,1,"Sistema frenante","Pastiglie Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (325,1,"Sistema frenante","Pinza Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (326,1,"Sistema frenante","Pompa Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (327,1,"Sistema frenante","Supporto Pinza Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (328,1,"Sistema frenante","Tubi Freno","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (329,1,"Sistemi per il comfort ","Alzacristalli","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (330,1,"Sospensione / Ammortizzazione","Ammortizzatori","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (331,1,"Sospensione / Ammortizzazione","Kit Sospensioni","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (332,1,"Sospensione / Ammortizzazione","Molla Ammortizzatore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (333,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (334,1,"Sospensione / Ammortizzazione","Biellette Barra Stabilizzatrice","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (335,1,"Sospensione / Ammortizzazione","Braccio Oscillante","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (336,1,"Sospensione / Ammortizzazione","Cuscinetto Ruota","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (337,1,"Sospensione / Ammortizzazione","Fuso Dell'asse","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (338,1,"Sospensione / Ammortizzazione","Gommini Barra Stabilizzatrice","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (339,1,"Sospensione / Ammortizzazione","Mozzo Ruota","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (340,1,"Sospensione / Ammortizzazione","Silent Block","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (341,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (342,1,"Sospensione / Ammortizzazione","Supporto Assale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (343,1,"Sospensione / Ammortizzazione","Testina Braccio Oscillante","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (344,1,"Sterzo","Cuffia Scatola Sterzo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (345,1,"Sterzo","Filtro Idraulico Sterzo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (346,1,"Sterzo","Servosterzo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (347,1,"Sterzo","Snodo Assiale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (348,1,"Sterzo","Testina dello Sterzo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (349,1,"Sterzo","Tirante Sterzo","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (350,1,"Tergicristalli","Tergicristalli","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (351,1,"Equipaggiamento interno","Accessori","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (352,1,"Equipaggiamento interno","Alzacristalli","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (353,1,"Equipaggiamento interno","Leveraggio Manuale / a Pedale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (354,1,"Equipaggiamento interno","Vano Bagagli / di Carico","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (355,1,"Trasmissione a cinghia","Cinghia Trapezoidale.M","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (356,1,"Trasmissione a cinghia","Pompa Acqua + Kit Cinghia Distribuzione.M","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (357,1,"Trasmissione a cinghia","Rullo Tendicinghia.M","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (358,1,"Trasmissione finale","Kit Giunto Omocinetico","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (359,1,"Trasmissione finale","Parti di Fissaggio/Accessori","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (360,1,"Trasmissione finale","Semiasse","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (361,1,"Trasmissione finale","Soffietto","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (362,1,"Trasmissione finale","Tripode","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (363,1,"Filtro","Filtro Aria","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (364,1,"Filtro","Filtro Carburante","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (365,1,"Filtro","Filtro Idraulico","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (366,1,"Filtro","Filtro Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",38,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (367,1,"Frizione / parti di montaggio","Cavo Frizione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (368,1,"Frizione / parti di montaggio","Disco Frizione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (369,1,"Frizione / parti di montaggio","Dispositivo Disinnesto Centrale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (370,1,"Frizione / parti di montaggio","Kit Frizione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (371,1,"Frizione / parti di montaggio","Pedali e Copripedale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (372,1,"Frizione / parti di montaggio","Pompa Frizione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (373,1,"Frizione / parti di montaggio","Spingidisco","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (374,1,"Frizione / parti di montaggio","Сuscinetto Reggispinta","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (375,1,"impianto alimentazione carburante","Filtro Carburante","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (376,1,"impianto alimentazione carburante","Pompa Carburante","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (377,1,"Impianto di accensione","Bobina","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (378,1,"Impianto di accensione","Candele","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (379,1,"Impianto di accensione","Cavi Candele","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (380,1,"Impianto di accensione","Spinterogeno e Componenti","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (381,1,"Impianto elettrico","Alternatore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (382,1,"Impianto elettrico","Alternatore Componenti","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",38,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (383,1,"Impianto elettrico","Batteria","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (384,1,"Impianto elettrico","Cavo Tachimetro","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (385,1,"Impianto elettrico","Elettromagnete Motorino Avviamento","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (386,1,"Impianto elettrico","Fari","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (387,1,"Impianto elettrico","Frecce","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (388,1,"Impianto elettrico","Interruttore / Regolatore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (389,1,"Impianto elettrico","Lampadina Faro Principale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (390,1,"Impianto elettrico","Lampadina Freccia","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (391,1,"Impianto elettrico","Lampadina Luce Posteriore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (392,1,"Impianto elettrico","Lampadina Luce Targa","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (393,1,"Impianto elettrico","Motorino D'avviamento","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (394,1,"Impianto elettrico","Regolatore di Tensione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (395,1,"Impianto elettrico","Relè","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (396,1,"Impianto elettrico","Relè Frecce","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (397,1,"Impianto gas scarico","Guarnizione Tubo Gas Scarico","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (398,1,"Impianto gas scarico","Manicotto saldatura","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (399,1,"Impianto gas scarico","Marmitta","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (400,1,"Impianto gas scarico","Morsetto","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (401,1,"Impianto gas scarico","Nastro di Gomma","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (402,1,"Impianto gas scarico","Pezzo per Bloccaggio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (403,1,"Impianto gas scarico","Staffa","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (404,1,"Impianto gas scarico","Supporto","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (405,1,"Impianto gas scarico","Tampone in Gomma","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (406,1,"Impianto gas scarico","Tubi Gas Scarico","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (407,1,"Motore","Albero a Canne","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (408,1,"Motore","Asta Livello Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (409,1,"Motore","Bronzina Piede di Biella","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (410,1,"Motore","Bronzine Motore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (411,1,"Motore","Bulbo Pressione Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (412,1,"Motore","Bulloni Testata","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (413,1,"Motore","Cilindro / Pistone","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (414,1,"Motore","Cinghia Distribuzione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (415,1,"Motore","Cinghia Trapezoidale","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (416,1,"Motore","Comando valvole","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (417,1,"Motore","Coperchio Punterie","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (418,1,"Motore","Fasce Elastiche","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (419,1,"Motore","Filtro Aria","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (420,1,"Motore","Filtro Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (421,1,"Motore","Gommini Valvole","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (422,1,"Motore","Guarnizione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (423,1,"Motore","Guarnizione testata","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (424,1,"Motore","Guarnizione Carter","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (425,1,"Motore","Guarnizione Collettore Aspirazione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (426,1,"Motore","Guarnizione Collettore Scarico","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (427,1,"Motore","Guarnizione Coperchio Punterie","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (428,1,"Motore","Guarnizione Coppa Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (429,1,"Motore","Guarnizione Tenuta Circuito Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (430,1,"Motore","Guarnizione Testata","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (431,1,"Motore","Guida / Guarnizione / Regolazione Valvole","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (432,1,"Motore","Impianto Elettrico Motore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",38,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (433,1,"Motore","Kit Cinghia Distribuzione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (434,1,"Motore","Kit Completo di Guarnizioni","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (435,1,"Motore","Paraolio Albero A Camme","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (436,1,"Motore","Paraolio Albero Motore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (437,1,"Motore","Paraolio Albero a Camme","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (438,1,"Motore","Pistone","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (439,1,"Motore","Pompa Acqua + Kit Cinghia Distribuzione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (440,1,"Motore","Pulegge Albero a Gomiti","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (441,1,"Motore","Punterie","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (442,1,"Motore","Rullo Tendicinghia","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (443,1,"Motore","Semicuscinetto Albero a Gomiti","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (444,1,"Motore","Supporto Motore","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (445,1,"Motore","Tappo Coppa Olio e Guarnizione Tappo Coppa Olio","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (446,1,"Motore","Tappo Monoblocco","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (447,1,"Motore","Valvola di Scarico e Valvola Aspirazione","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (448,1,"Guarnizioni","Kit Riparazione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (449,1,"Guarnizioni","Pomello del Cambio e Componenti","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (450,1,"Preparazione carburante","Guarnizioni","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (451,1,"Preparazione carburante","Kit riparazione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (452,1,"Raffreddamento","Pompa Acqua","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (453,1,"Raffreddamento","Radiatore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (454,1,"Raffreddamento","Radiatore Riscaldamento","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (455,1,"Raffreddamento","Sensori e Interruttori","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (456,1,"Raffreddamento","Termostato","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (457,1,"Raffreddamento","Tubo Radiatore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (458,1,"Raffreddamento","Vaschetta Radiatore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (459,1,"Riscaldamento / Aerazion","Radiatore Riscaldamento","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (460,1,"Sistema chiusura","Serratura","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (461,1,"Sistema chiusura","Serrature Abitacolo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (462,1,"Sistema frenante","Accessori / Componenti","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (463,1,"Sistema frenante","Cavo Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (464,1,"Sistema frenante","Cilindretto Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (465,1,"Sistema frenante","Cilindro Freno Ruota","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (466,1,"Sistema frenante","Correttore Frenata","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (467,1,"Sistema frenante","Dischi Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (468,1,"Sistema frenante","Freno a Tamburo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (469,1,"Sistema frenante","Ganasce Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (470,1,"Sistema frenante","Interruttore Stop","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (471,1,"Sistema frenante","Kit Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (472,1,"Sistema frenante","Olio Freni","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (473,1,"Sistema frenante","Pastiglie Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (474,1,"Sistema frenante","Pinza Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (475,1,"Sistema frenante","Pompa Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (476,1,"Sistema frenante","Supporto Pinza Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (477,1,"Sistema frenante","Tubi Freno","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (478,1,"Sistemi per il comfort ","Alzacristalli","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (479,1,"Sospensione / Ammortizzazione","Ammortizzatori","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (480,1,"Sospensione / Ammortizzazione","Kit Sospensioni","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (481,1,"Sospensione / Ammortizzazione","Molla Ammortizzatore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (482,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (483,1,"Sospensione / Ammortizzazione","Biellette Barra Stabilizzatrice","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (484,1,"Sospensione / Ammortizzazione","Braccio Oscillante","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",37,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (485,1,"Sospensione / Ammortizzazione","Cuscinetto Ruota","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (486,1,"Sospensione / Ammortizzazione","Fuso Dell'asse","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (487,1,"Sospensione / Ammortizzazione","Gommini Barra Stabilizzatrice","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (488,1,"Sospensione / Ammortizzazione","Mozzo Ruota","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (489,1,"Sospensione / Ammortizzazione","Silent Block","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (490,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (491,1,"Sospensione / Ammortizzazione","Supporto Assale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (492,1,"Sospensione / Ammortizzazione","Testina Braccio Oscillante","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (493,1,"Sterzo","Cuffia Scatola Sterzo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (494,1,"Sterzo","Filtro Idraulico Sterzo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (495,1,"Sterzo","Servosterzo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (496,1,"Sterzo","Snodo Assiale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (497,1,"Sterzo","Testina dello Sterzo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (498,1,"Sterzo","Tirante Sterzo","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (499,1,"Tergicristalli","Tergicristalli","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (500,1,"Equipaggiamento interno","Accessori","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",38,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (501,1,"Equipaggiamento interno","Alzacristalli","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (502,1,"Equipaggiamento interno","Leveraggio Manuale / a Pedale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (503,1,"Equipaggiamento interno","Vano Bagagli / di Carico","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (504,1,"Trasmissione a cinghia","Cinghia Trapezoidale.M","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (505,1,"Trasmissione a cinghia","Pompa Acqua + Kit Cinghia Distribuzione.M","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (506,1,"Trasmissione a cinghia","Rullo Tendicinghia.M","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (507,1,"Trasmissione finale","Kit Giunto Omocinetico","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (508,1,"Trasmissione finale","Parti di Fissaggio/Accessori","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (509,1,"Trasmissione finale","Semiasse","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (510,1,"Trasmissione finale","Soffietto","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (511,1,"Trasmissione finale","Tripode","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (512,1,"Filtro","Filtro Aria","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (513,1,"Filtro","Filtro Carburante","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (514,1,"Filtro","Filtro Idraulico","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (515,1,"Filtro","Filtro Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (516,1,"Frizione / parti di montaggio","Cavo Frizione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (517,1,"Frizione / parti di montaggio","Disco Frizione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (518,1,"Frizione / parti di montaggio","Dispositivo Disinnesto Centrale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (519,1,"Frizione / parti di montaggio","Kit Frizione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (520,1,"Frizione / parti di montaggio","Pedali e Copripedale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (521,1,"Frizione / parti di montaggio","Pompa Frizione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (522,1,"Frizione / parti di montaggio","Spingidisco","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (523,1,"Frizione / parti di montaggio","Сuscinetto Reggispinta","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (524,1,"impianto alimentazione carburante","Filtro Carburante","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (525,1,"impianto alimentazione carburante","Pompa Carburante","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (526,1,"Impianto di accensione","Bobina","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (527,1,"Impianto di accensione","Candele","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (528,1,"Impianto di accensione","Cavi Candele","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (529,1,"Impianto di accensione","Spinterogeno e Componenti","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (530,1,"Impianto elettrico","Alternatore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (531,1,"Impianto elettrico","Alternatore Componenti","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (532,1,"Impianto elettrico","Batteria","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (533,1,"Impianto elettrico","Cavo Tachimetro","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (534,1,"Impianto elettrico","Elettromagnete Motorino Avviamento","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (535,1,"Impianto elettrico","Fari","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (536,1,"Impianto elettrico","Frecce","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (537,1,"Impianto elettrico","Interruttore / Regolatore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (538,1,"Impianto elettrico","Lampadina Faro Principale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (539,1,"Impianto elettrico","Lampadina Freccia","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (540,1,"Impianto elettrico","Lampadina Luce Posteriore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (541,1,"Impianto elettrico","Lampadina Luce Targa","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (542,1,"Impianto elettrico","Motorino D'avviamento","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (543,1,"Impianto elettrico","Regolatore di Tensione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",46,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (544,1,"Impianto elettrico","Relè","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (545,1,"Impianto elettrico","Relè Frecce","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (546,1,"Impianto gas scarico","Guarnizione Tubo Gas Scarico","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (547,1,"Impianto gas scarico","Manicotto saldatura","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (548,1,"Impianto gas scarico","Marmitta","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (549,1,"Impianto gas scarico","Morsetto","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (550,1,"Impianto gas scarico","Nastro di Gomma","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (551,1,"Impianto gas scarico","Pezzo per Bloccaggio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (552,1,"Impianto gas scarico","Staffa","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (553,1,"Impianto gas scarico","Supporto","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (554,1,"Impianto gas scarico","Tampone in Gomma","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (555,1,"Impianto gas scarico","Tubi Gas Scarico","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (556,1,"Motore","Albero a Canne","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",32,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (557,1,"Motore","Asta Livello Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",50,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (558,1,"Motore","Bronzina Piede di Biella","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",38,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (559,1,"Motore","Bronzine Motore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (560,1,"Motore","Bulbo Pressione Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (561,1,"Motore","Bulloni Testata","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (562,1,"Motore","Cilindro / Pistone","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (563,1,"Motore","Cinghia Distribuzione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",43,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (564,1,"Motore","Cinghia Trapezoidale","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",44,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (565,1,"Motore","Comando valvole","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (566,1,"Motore","Coperchio Punterie","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (567,1,"Motore","Fasce Elastiche","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",40,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (568,1,"Motore","Filtro Aria","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (569,1,"Motore","Filtro Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (570,1,"Motore","Gommini Valvole","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (571,1,"Motore","Guarnizione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (572,1,"Motore","Guarnizione testata","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (573,1,"Motore","Guarnizione Carter","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",31,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (574,1,"Motore","Guarnizione Collettore Aspirazione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",47,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (575,1,"Motore","Guarnizione Collettore Scarico","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (576,1,"Motore","Guarnizione Coperchio Punterie","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",49,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (577,1,"Motore","Guarnizione Coppa Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",48,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (578,1,"Motore","Guarnizione Tenuta Circuito Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",34,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (579,1,"Motore","Guarnizione Testata","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",35,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (580,1,"Motore","Guida / Guarnizione / Regolazione Valvole","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (581,1,"Motore","Impianto Elettrico Motore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (582,1,"Motore","Kit Cinghia Distribuzione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",36,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (583,1,"Motore","Kit Completo di Guarnizioni","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",38,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (584,1,"Motore","Paraolio Albero A Camme","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (585,1,"Motore","Paraolio Albero Motore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (586,1,"Motore","Paraolio Albero a Camme","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (587,1,"Motore","Pistone","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (588,1,"Motore","Pompa Acqua + Kit Cinghia Distribuzione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (589,1,"Motore","Pulegge Albero a Gomiti","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",33,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (590,1,"Motore","Punterie","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",39,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (591,1,"Motore","Rullo Tendicinghia","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",41,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (592,1,"Motore","Semicuscinetto Albero a Gomiti","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",30,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (593,1,"Motore","Supporto Motore","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (594,1,"Motore","Tappo Coppa Olio e Guarnizione Tappo Coppa Olio","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (595,1,"Motore","Tappo Monoblocco","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",42,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (596,1,"Motore","Valvola di Scarico e Valvola Aspirazione","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP",45,"ARBO s.r.l");
INSERT INTO Catalogo VALUES (597,1,"Guarnizioni","Kit Riparazione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (598,1,"Guarnizioni","Pomello del Cambio e Componenti","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (599,1,"Preparazione carburante","Guarnizioni","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (600,1,"Preparazione carburante","Kit riparazione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",33,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (601,1,"Raffreddamento","Pompa Acqua","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (602,1,"Raffreddamento","Radiatore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",30,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (603,1,"Raffreddamento","Radiatore Riscaldamento","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",36,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (604,1,"Raffreddamento","Sensori e Interruttori","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (605,1,"Raffreddamento","Termostato","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (606,1,"Raffreddamento","Tubo Radiatore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (607,1,"Raffreddamento","Vaschetta Radiatore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (608,1,"Riscaldamento / Aerazion","Radiatore Riscaldamento","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",30,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (609,1,"Sistema chiusura","Serratura","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (610,1,"Sistema chiusura","Serrature Abitacolo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (611,1,"Sistema frenante","Accessori / Componenti","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (612,1,"Sistema frenante","Cavo Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",41,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (613,1,"Sistema frenante","Cilindretto Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",41,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (614,1,"Sistema frenante","Cilindro Freno Ruota","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (615,1,"Sistema frenante","Correttore Frenata","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",40,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (616,1,"Sistema frenante","Dischi Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (617,1,"Sistema frenante","Freno a Tamburo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (618,1,"Sistema frenante","Ganasce Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",40,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (619,1,"Sistema frenante","Interruttore Stop","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (620,1,"Sistema frenante","Kit Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (621,1,"Sistema frenante","Olio Freni","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (622,1,"Sistema frenante","Pastiglie Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",36,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (623,1,"Sistema frenante","Pinza Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (624,1,"Sistema frenante","Pompa Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (625,1,"Sistema frenante","Supporto Pinza Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (626,1,"Sistema frenante","Tubi Freno","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (627,1,"Sistemi per il comfort ","Alzacristalli","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (628,1,"Sospensione / Ammortizzazione","Ammortizzatori","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",39,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (629,1,"Sospensione / Ammortizzazione","Kit Sospensioni","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (630,1,"Sospensione / Ammortizzazione","Molla Ammortizzatore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (631,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (632,1,"Sospensione / Ammortizzazione","Biellette Barra Stabilizzatrice","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (633,1,"Sospensione / Ammortizzazione","Braccio Oscillante","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (634,1,"Sospensione / Ammortizzazione","Cuscinetto Ruota","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (635,1,"Sospensione / Ammortizzazione","Fuso Dell'asse","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (636,1,"Sospensione / Ammortizzazione","Gommini Barra Stabilizzatrice","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (637,1,"Sospensione / Ammortizzazione","Mozzo Ruota","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",36,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (638,1,"Sospensione / Ammortizzazione","Silent Block","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",39,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (639,1,"Sospensione / Ammortizzazione","Supporto Ammortizzatore e Cuscinetto","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",47,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (640,1,"Sospensione / Ammortizzazione","Supporto Assale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",33,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (641,1,"Sospensione / Ammortizzazione","Testina Braccio Oscillante","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",39,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (642,1,"Sterzo","Cuffia Scatola Sterzo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",40,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (643,1,"Sterzo","Filtro Idraulico Sterzo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (644,1,"Sterzo","Servosterzo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (645,1,"Sterzo","Snodo Assiale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (646,1,"Sterzo","Testina dello Sterzo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (647,1,"Sterzo","Tirante Sterzo","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",41,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (648,1,"Tergicristalli","Tergicristalli","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",33,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (649,1,"Equipaggiamento interno","Accessori","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",30,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (650,1,"Equipaggiamento interno","Alzacristalli","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (651,1,"Equipaggiamento interno","Leveraggio Manuale / a Pedale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (652,1,"Equipaggiamento interno","Vano Bagagli / di Carico","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (653,1,"Trasmissione a cinghia","Cinghia Trapezoidale.M","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (654,1,"Trasmissione a cinghia","Pompa Acqua + Kit Cinghia Distribuzione.M","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (655,1,"Trasmissione a cinghia","Rullo Tendicinghia.M","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (656,1,"Trasmissione finale","Kit Giunto Omocinetico","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",36,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (657,1,"Trasmissione finale","Parti di Fissaggio/Accessori","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",40,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (658,1,"Trasmissione finale","Semiasse","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (659,1,"Trasmissione finale","Soffietto","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (660,1,"Trasmissione finale","Tripode","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (661,1,"Filtro","Filtro Aria","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (662,1,"Filtro","Filtro Carburante","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",35,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (663,1,"Filtro","Filtro Idraulico","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (664,1,"Filtro","Filtro Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (665,1,"Frizione / parti di montaggio","Cavo Frizione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (666,1,"Frizione / parti di montaggio","Disco Frizione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",41,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (667,1,"Frizione / parti di montaggio","Dispositivo Disinnesto Centrale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (668,1,"Frizione / parti di montaggio","Kit Frizione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (669,1,"Frizione / parti di montaggio","Pedali e Copripedale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (670,1,"Frizione / parti di montaggio","Pompa Frizione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",35,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (671,1,"Frizione / parti di montaggio","Spingidisco","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (672,1,"Frizione / parti di montaggio","Сuscinetto Reggispinta","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",47,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (673,1,"impianto alimentazione carburante","Filtro Carburante","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (674,1,"impianto alimentazione carburante","Pompa Carburante","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",33,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (675,1,"Impianto di accensione","Bobina","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (676,1,"Impianto di accensione","Candele","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (677,1,"Impianto di accensione","Cavi Candele","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (678,1,"Impianto di accensione","Spinterogeno e Componenti","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (679,1,"Impianto elettrico","Alternatore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (680,1,"Impianto elettrico","Alternatore Componenti","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (681,1,"Impianto elettrico","Batteria","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (682,1,"Impianto elettrico","Cavo Tachimetro","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (683,1,"Impianto elettrico","Elettromagnete Motorino Avviamento","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (684,1,"Impianto elettrico","Fari","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (685,1,"Impianto elettrico","Frecce","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (686,1,"Impianto elettrico","Interruttore / Regolatore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (687,1,"Impianto elettrico","Lampadina Faro Principale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (688,1,"Impianto elettrico","Lampadina Freccia","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (689,1,"Impianto elettrico","Lampadina Luce Posteriore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (690,1,"Impianto elettrico","Lampadina Luce Targa","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (691,1,"Impianto elettrico","Motorino D'avviamento","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (692,1,"Impianto elettrico","Regolatore di Tensione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",40,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (693,1,"Impianto elettrico","Relè","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (694,1,"Impianto elettrico","Relè Frecce","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (695,1,"Impianto gas scarico","Guarnizione Tubo Gas Scarico","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",38,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (696,1,"Impianto gas scarico","Manicotto saldatura","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (697,1,"Impianto gas scarico","Marmitta","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",39,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (698,1,"Impianto gas scarico","Morsetto","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",40,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (699,1,"Impianto gas scarico","Nastro di Gomma","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",38,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (700,1,"Impianto gas scarico","Pezzo per Bloccaggio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (701,1,"Impianto gas scarico","Staffa","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",47,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (702,1,"Impianto gas scarico","Supporto","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (703,1,"Impianto gas scarico","Tampone in Gomma","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",35,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (704,1,"Impianto gas scarico","Tubi Gas Scarico","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (705,1,"Motore","Albero a Canne","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (706,1,"Motore","Asta Livello Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",30,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (707,1,"Motore","Bronzina Piede di Biella","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (708,1,"Motore","Bronzine Motore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",30,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (709,1,"Motore","Bulbo Pressione Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (710,1,"Motore","Bulloni Testata","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",35,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (711,1,"Motore","Cilindro / Pistone","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (712,1,"Motore","Cinghia Distribuzione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (713,1,"Motore","Cinghia Trapezoidale","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",47,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (714,1,"Motore","Comando valvole","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",39,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (715,1,"Motore","Coperchio Punterie","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (716,1,"Motore","Fasce Elastiche","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",43,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (717,1,"Motore","Filtro Aria","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",50,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (718,1,"Motore","Filtro Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (719,1,"Motore","Gommini Valvole","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (720,1,"Motore","Guarnizione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",31,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (721,1,"Motore","Guarnizione testata","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",41,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (722,1,"Motore","Guarnizione Carter","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (723,1,"Motore","Guarnizione Collettore Aspirazione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (724,1,"Motore","Guarnizione Collettore Scarico","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (725,1,"Motore","Guarnizione Coperchio Punterie","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",41,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (726,1,"Motore","Guarnizione Coppa Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",47,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (727,1,"Motore","Guarnizione Tenuta Circuito Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (728,1,"Motore","Guarnizione Testata","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (729,1,"Motore","Guida / Guarnizione / Regolazione Valvole","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",42,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (730,1,"Motore","Impianto Elettrico Motore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",38,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (731,1,"Motore","Kit Cinghia Distribuzione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",44,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (732,1,"Motore","Kit Completo di Guarnizioni","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",47,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (733,1,"Motore","Paraolio Albero A Camme","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",39,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (734,1,"Motore","Paraolio Albero Motore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",49,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (735,1,"Motore","Paraolio Albero a Camme","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (736,1,"Motore","Pistone","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (737,1,"Motore","Pompa Acqua + Kit Cinghia Distribuzione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (738,1,"Motore","Pulegge Albero a Gomiti","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (739,1,"Motore","Punterie","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (740,1,"Motore","Rullo Tendicinghia","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",34,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (741,1,"Motore","Semicuscinetto Albero a Gomiti","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",37,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (742,1,"Motore","Supporto Motore","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",48,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (743,1,"Motore","Tappo Coppa Olio e Guarnizione Tappo Coppa Olio","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",32,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (744,1,"Motore","Tappo Monoblocco","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",45,"AUTOCAR LAGUNA");
INSERT INTO Catalogo VALUES (745,1,"Motore","Valvola di Scarico e Valvola Aspirazione","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP",46,"AUTOCAR LAGUNA");


/*popolamento StoricoOrdine*/
INSERT INTO Veicolo VALUES ("YV970UT","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)","VSFKLW45R24M153J");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"YV970UT",Meccanico(),"2017-05-25");
INSERT INTO PezziNecessari values(1,168,"Correttore Frenata",2,0,40,"2017-05-25");
INSERT INTO PezziNecessari values(1,201,"Tergicristalli",2,0,43,"2017-05-25");
INSERT INTO PezziNecessari values(1,151,"Pomello del Cambio e Componenti",1,0,41,"2017-05-25");
INSERT INTO PezziNecessari values(1,296,"Tappo Coppa Olio e Guarnizione Tappo Coppa Olio",1,0,48,"2017-05-25");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=1;

INSERT INTO Veicolo VALUES ("AV416VM","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP","ANYKZZ79N27M476H");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"AV416VM",Meccanico(),"2017-05-25");
INSERT INTO PezziNecessari values(2,318,"Dischi Freno",1,0,41,"2017-05-25");
INSERT INTO PezziNecessari values(2,308,"Tubo Radiatore",1,0,36,"2017-05-25");
INSERT INTO PezziNecessari values(2,319,"Freno a Tamburo",2,0,30,"2017-05-25");
INSERT INTO PezziNecessari values(2,332,"Molla Ammortizzatore",1,0,50,"2017-05-25");
INSERT INTO PezziNecessari values(2,334,"Biellette Barra Stabilizzatrice",1,0,40,"2017-05-25");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=2;

INSERT INTO Veicolo VALUES ("RV629PW","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP","OAEZKJ87U08K580Q");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"RV629PW",Meccanico(),"2017-05-25");
INSERT INTO PezziNecessari values(3,467,"Dischi Freno",2,0,41,"2017-05-25");
INSERT INTO PezziNecessari values(3,481,"Molla Ammortizzatore",1,0,30,"2017-05-25");
INSERT INTO PezziNecessari values(3,485,"Cuscinetto Ruota",2,0,46,"2017-05-25");
INSERT INTO PezziNecessari values(3,503,"Vano Bagagli / di Carico",1,0,30,"2017-05-25");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=3;

INSERT INTO Veicolo VALUES ("AN098ER","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP","BWJRRC34D17X910B");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"AN098ER",Meccanico(),"2017-05-25");
INSERT INTO PezziNecessari values(4,603,"Radiatore Riscaldamento",2,0,36,"2017-05-25");
INSERT INTO PezziNecessari values(4,629,"Kit Sospensioni",1,0,49,"2017-05-25");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=4;

UPDATE StoricoOrdine SET Manodopera = 4 WHERE NROrdine= 1;
UPDATE StoricoOrdine SET Manodopera = 2 WHERE NROrdine= 2;
UPDATE StoricoOrdine SET Manodopera = 3 WHERE NROrdine= 3;

INSERT INTO Veicolo VALUES ("AE176WU","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000","GHOXHL33M22B430A");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"AE176WU",Meccanico(),"2017-05-25");
INSERT INTO PezziNecessari values(5,98,"Relè Frecce",1,0,38,"2017-05-25");
INSERT INTO PezziNecessari values(5,65,"Filtro Aria",2,0,35,"2017-05-25");
INSERT INTO PezziNecessari values(5,149,"Valvola di Scarico e Valvola Aspirazione",1,0,33,"2017-05-25");
INSERT INTO PezziNecessari values(5,9,"Termostato",1,0,40,"2017-05-25");
INSERT INTO PezziNecessari values(5,111,"Bronzina Piede di Biella",1,0,48,"2017-05-25");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=5;

UPDATE StoricoOrdine SET Manodopera = 5 WHERE NROrdine= 4;
UPDATE StoricoOrdine SET Manodopera = 7 WHERE NROrdine= 5;

INSERT INTO Veicolo VALUES ("LX472ML","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)","IQDOCS97P08I934D");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"LX472ML",Meccanico(),"2017-05-26");
INSERT INTO PezziNecessari values(6,168,"Correttore Frenata",2,0,40,"2017-05-26");
INSERT INTO PezziNecessari values(6,201,"Tergicristalli",2,0,43,"2017-05-26");
INSERT INTO PezziNecessari values(6,151,"Pomello del Cambio e Componenti",1,0,41,"2017-05-26");
INSERT INTO PezziNecessari values(6,296,"Tappo Coppa Olio e Guarnizione Tappo Coppa Olio",1,0,48,"2017-05-26");
INSERT INTO PezziNecessari values(6,165,"Cavo Freno",2,0,48,"2017-05-26");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=6;

INSERT INTO Veicolo VALUES ("LB545PR","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP","JHMYAE65Y02D977F");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"LB545PR",Meccanico(),"2017-05-26");
INSERT INTO PezziNecessari values(7,318,"Dischi Freno",2,0,41,"2017-05-26");
INSERT INTO PezziNecessari values(7,308,"Tubo Radiatore",2,0,36,"2017-05-26");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=7;

INSERT INTO Veicolo VALUES ("PT508DL","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP","YUQAMA57R27D159Q");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"PT508DL",Meccanico(),"2017-05-26");
INSERT INTO PezziNecessari values(8,467,"Dischi Freno",2,0,41,"2017-05-26");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=8;

INSERT INTO Veicolo VALUES ("MS173BM","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP","OXTKDM06K19U272E");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"MS173BM",Meccanico(),"2017-05-26");
INSERT INTO PezziNecessari values(9,603,"Radiatore Riscaldamento",2,0,36,"2017-05-26");
INSERT INTO PezziNecessari values(9,629,"Kit Sospensioni",2,0,49,"2017-05-26");
INSERT INTO PezziNecessari values(9,651,"Leveraggio Manuale / a Pedale",1,0,50,"2017-05-26");
INSERT INTO PezziNecessari values(9,648,"Tergicristalli",1,0,33,"2017-05-26");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=9;

UPDATE StoricoOrdine SET Manodopera = 1 WHERE NROrdine= 8;

INSERT INTO Veicolo VALUES ("QI346BI","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000","GXDQHN91U07Q793M");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"QI346BI",Meccanico(),"2017-05-26");
INSERT INTO PezziNecessari values(10,98,"Relè Frecce",1,0,38,"2017-05-26");
INSERT INTO PezziNecessari values(10,65,"Filtro Aria",1,0,35,"2017-05-26");
INSERT INTO PezziNecessari values(10,149,"Valvola di Scarico e Valvola Aspirazione",1,0,33,"2017-05-26");
INSERT INTO PezziNecessari values(10,9,"Termostato",2,0,40,"2017-05-26");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=10;

UPDATE StoricoOrdine SET Manodopera = 6 WHERE NROrdine= 6;
UPDATE StoricoOrdine SET Manodopera = 4 WHERE NROrdine= 7;
UPDATE StoricoOrdine SET Manodopera = 6 WHERE NROrdine= 9;

INSERT INTO Veicolo VALUES ("DE779DW","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)","OJQPSR82J15L722Q");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"DE779DW",Meccanico(),"2017-05-26");
INSERT INTO PezziNecessari values(11,168,"Correttore Frenata",1,0,40,"2017-05-26");
INSERT INTO PezziNecessari values(11,201,"Tergicristalli",2,0,43,"2017-05-26");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=11;

INSERT INTO Veicolo VALUES ("UF255FE","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP","IYCZNE80F09T729J");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"UF255FE",Meccanico(),"2017-05-27");
INSERT INTO PezziNecessari values(12,332,"Molla Ammortizzatore",2,0,50,"2017-05-27");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=12;

UPDATE StoricoOrdine SET Manodopera = 5 WHERE NROrdine= 10;

INSERT INTO Veicolo VALUES ("HE159UO","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP","KUFOBO63T06N728A");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"HE159UO",Meccanico(),"2017-05-27");
INSERT INTO PezziNecessari values(13,481,"Molla Ammortizzatore",1,0,30,"2017-05-27");
INSERT INTO PezziNecessari values(13,503,"Vano Bagagli / di Carico",2,0,30,"2017-05-27");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=13;

INSERT INTO Veicolo VALUES ("GX083XQ","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP","ZRAIBK26Z12S151B");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"GX083XQ",Meccanico(),"2017-05-27");
INSERT INTO PezziNecessari values(14,603,"Radiatore Riscaldamento",2,0,36,"2017-05-27");
INSERT INTO PezziNecessari values(14,629,"Kit Sospensioni",1,0,49,"2017-05-27");
INSERT INTO PezziNecessari values(14,654,"Pompa Acqua + Kit Cinghia Distribuzione",1,0,31,"2017-05-27");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=14;

UPDATE StoricoOrdine SET Manodopera = 3 WHERE NROrdine= 11;
UPDATE StoricoOrdine SET Manodopera = 1 WHERE NROrdine= 12;
UPDATE StoricoOrdine SET Manodopera = 4 WHERE NROrdine= 13;

INSERT INTO Veicolo VALUES ("OK208NM","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000","KXYRUH41E02F397D");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"OK208NM",Meccanico(),"2017-05-27");
INSERT INTO PezziNecessari values(15,65,"Filtro Aria",1,0,31,"2017-05-27");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=15;

INSERT INTO Veicolo VALUES ("BJ415GW","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)","GXDQHN91U07Q793M");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"BJ415GW",Meccanico(),"2017-05-28");
INSERT INTO PezziNecessari values(16,201,"Tergicristalli",2,0,43,"2017-05-28");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=16;

UPDATE StoricoOrdine SET Manodopera = 5 WHERE NROrdine= 14;

INSERT INTO Veicolo VALUES ("RG429QD","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP","YRFJPN34V12X920N");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"RG429QD",Meccanico(),"2017-05-28");
INSERT INTO PezziNecessari values(17,319,"Freno a Tamburo",1,0,30,"2017-05-28");
INSERT INTO PezziNecessari values(17,332,"Molla Ammortizzatore",2,0,50,"2017-05-28");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=17;

UPDATE StoricoOrdine SET Manodopera = 1 WHERE NROrdine= 15;
UPDATE StoricoOrdine SET Manodopera = 1 WHERE NROrdine= 16;

INSERT INTO Veicolo VALUES ("II519IM","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP","MROFYK58F27O229C");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"II519IM",Meccanico(),"2017-05-28");
INSERT INTO PezziNecessari values(18,481,"Molla Ammortizzatore",2,0,30,"2017-05-28");
INSERT INTO PezziNecessari values(18,485,"Cuscinetto Ruota",2,0,46,"2017-05-28");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=18;

UPDATE StoricoOrdine SET Manodopera = 4 WHERE NROrdine= 17;

INSERT INTO Veicolo VALUES ("TI798QV","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP","MCZDCO85C03Q217D");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"TI798QV",Meccanico(),"2017-05-28");
INSERT INTO PezziNecessari values(19,603,"Radiatore Riscaldamento",2,0,36,"2017-05-28");
INSERT INTO PezziNecessari values(19,629,"Kit Sospensioni",2,0,49,"2017-05-28");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=19;

INSERT INTO Veicolo VALUES ("EA363JN","FIAT","DOBLO (119)","1.3 MJTD 16V 199A2000","MRIASG95R06P914H");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"EA363JN",Meccanico(),"2017-05-29");
INSERT INTO PezziNecessari values(20,65,"Filtro Aria",2,0,31,"2017-05-29");
INSERT INTO PezziNecessari values(20,149,"Valvola di Scarico e Valvola Aspirazione",1,0,30,"2017-05-29");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=20;

UPDATE StoricoOrdine SET Manodopera = 3 WHERE NROrdine= 18;
UPDATE StoricoOrdine SET Manodopera = 4 WHERE NROrdine= 19;

INSERT INTO Veicolo VALUES ("EP587ZW","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)","QMWNBK33H24S878E");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"EP587ZW",Meccanico(),"2017-05-29");
INSERT INTO PezziNecessari values(21,151,"Pomello del Cambio e Componenti",2,0,41,"2017-05-29");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=21;

INSERT INTO Veicolo VALUES ("NJ356PN","PEUGEOT","1007","1.4 HDI DV4TD - 50 KW / 68 HP","RDUXKE14H00K011H");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"NJ356PN",Meccanico(),"2017-05-29");
INSERT INTO PezziNecessari values(22,318,"Dischi Freno",2,0,41,"2017-05-29");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=22;

INSERT INTO Veicolo VALUES ("KD083TV","CITROEN","C3","1.4 HDI DV4TD - 50 KW / 68 HP","XLLURO99M23L836A");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"KD083TV",Meccanico(),"2017-05-29");
INSERT INTO PezziNecessari values(23,481,"Molla Ammortizzatore",1,0,30,"2017-05-29");
INSERT INTO PezziNecessari values(23,485,"Cuscinetto Ruota",1,0,46,"2017-05-29");
INSERT INTO PezziNecessari values(23,503,"Vano Bagagli / di Carico",2,0,30,"2017-05-29");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=23;

UPDATE StoricoOrdine SET Manodopera = 1 WHERE NROrdine= 20;
UPDATE StoricoOrdine SET Manodopera = 1 WHERE NROrdine= 21;
UPDATE StoricoOrdine SET Manodopera = 5 WHERE NROrdine= 22;

INSERT INTO Veicolo VALUES ("IP360JS","FORD","FOCUS","1.4 TDCI - 50 KW / 68 HP","CDKKRV91H11T832T");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"IP360JS",Meccanico(),"2017-05-30");
INSERT INTO PezziNecessari values(24,603,"Radiatore Riscaldamento",2,0,36,"2017-05-30");
INSERT INTO PezziNecessari values(24,629,"Kit Sospensioni",1,0,49,"2017-05-30");
INSERT INTO PezziNecessari values(24,614,"Cilindro Freno Ruota",1,0,43,"2017-05-30");
UPDATE Decisione SET Risultato = 'Positivo' WHERE NROrdine=24;

Update OrdinePendente set Quantita =Ricevuti (1,111) where CodicePezzo=111;
Update OrdinePendente set Quantita =Ricevuti (3,149) where CodicePezzo=149;
Update OrdinePendente set Quantita =Ricevuti (4,151) where CodicePezzo=151;
Update OrdinePendente set Quantita =Ricevuti (2,165) where CodicePezzo=165;
Update OrdinePendente set Quantita =Ricevuti (5,168) where CodicePezzo=168;
Update OrdinePendente set Quantita =Ricevuti (8,201) where CodicePezzo=201;
Update OrdinePendente set Quantita =Ricevuti (2,296) where CodicePezzo=296;
Update OrdinePendente set Quantita =Ricevuti (3,308) where CodicePezzo=308;
Update OrdinePendente set Quantita =Ricevuti (5,318) where CodicePezzo=318;
Update OrdinePendente set Quantita =Ricevuti (3,319) where CodicePezzo=319;
Update OrdinePendente set Quantita =Ricevuti (5,332) where CodicePezzo=332;
Update OrdinePendente set Quantita =Ricevuti (1,334) where CodicePezzo=334;
Update OrdinePendente set Quantita =Ricevuti (4,467) where CodicePezzo=467;
Update OrdinePendente set Quantita =Ricevuti (5,481) where CodicePezzo=481;
Update OrdinePendente set Quantita =Ricevuti (5,485) where CodicePezzo=485;
Update OrdinePendente set Quantita =Ricevuti (5,503) where CodicePezzo=503;
Update OrdinePendente set Quantita =Ricevuti (8,603) where CodicePezzo=603;
Update OrdinePendente set Quantita =Ricevuti (6,629) where CodicePezzo=629;
Update OrdinePendente set Quantita =Ricevuti (1,648) where CodicePezzo=648;
Update OrdinePendente set Quantita =Ricevuti (6,65) where CodicePezzo=65;
Update OrdinePendente set Quantita =Ricevuti (1,651) where CodicePezzo=651;
Update OrdinePendente set Quantita =Ricevuti (1,654) where CodicePezzo=654;
Update OrdinePendente set Quantita =Ricevuti (3,9) where CodicePezzo=9;
Update OrdinePendente set Quantita =Ricevuti (2,98) where CodicePezzo=98;

INSERT INTO Veicolo VALUES ("IX439HU","FIAT","DOBLO (119)","1.3 JTD 16V MULTIJET 188A9000","FZBUQE87O02H965V");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"IX439HU",Meccanico(),"2017-05-30");
INSERT INTO PezziNecessari values(25,98,"Relè Frecce",1,0,49,"2017-05-30");
INSERT INTO PezziNecessari values(25,65,"Filtro Aria",1,0,31,"2017-05-30");
INSERT INTO PezziNecessari values(25,149,"Valvola di Scarico e Valvola Aspirazione",1,0,30,"2017-06-30");

INSERT INTO Veicolo VALUES ("FR396RR","VOLKSWAGEN","Polo V","1.6 TDi CAYA 55KW(75PS/HP)","KUFOBO63T06N728A");
INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"FR396RR",Meccanico(),"2017-05-30");
INSERT INTO PezziNecessari values(26,168,"Correttore Frenata",2,0,40,"2017-05-30");
INSERT INTO PezziNecessari values(26,201,"Tergicristalli",2,0,43,"2017-05-30");
INSERT INTO PezziNecessari values(26,151,"Pomello del Cambio e Componenti",1,0,41,"2017-05-30");

INSERT INTO StoricoOrdine (NROrdine,Targa,Meccanico,DataInizioLavori) VALUES (prossimo(),"YV970UT",Meccanico(),"2017-05-30");

select*from StoricoOrdine;
select*from Decisione;
select*from PezziNecessari;
select*from OrdinePendente;
SELECT NROrdine, StatoOrdine (NROrdine) AS StatoOrdine from StoricoOrdine;
select Saldo() AS Saldo;

CALL Assegnazioni(Quantità,Codice_Pezzo);

/*numero di ore di lavoro per ciascun meccanico*/
SELECT I.Matricola, P.Nome, SUM(S.Manodopera) AS OreTotali, count(NROrdine) AS OrdiniTotali
FROM Dipendente I join StoricoOrdine S ON (I.Matricola = S.Meccanico), Persone P
WHERE P.CF = I.CF AND I.Mansione = 'Meccanico'
GROUP BY I.Matricola;



/*query per vedere se un meccanico è libero*/
select MIN(
						SELECT SUM(S.Manodopera) 
						FROM Dipendente I join StoricoOrdine S ON (I.Matricola = S.Meccanico), Persone P 
						WHERE P.CF = I.CF AND I.Mansione = 'Meccanico' GROUP BY I.Matricola
					 );

SELECT C.Fornitore, C.Marca, SUM(C.Prezzo) AS Guadagno, COUNT(*) AS NRpezziVenduti
FROM PezziNecessari P JOIN (SELECT * FROM Catalogo GROUP BY CodicePezzo) AS C on (P.CodicePezzo=C.CodicePezzo)
GROUP BY Fornitore
ORDER BY Guadagno desc;

select C.Categoria, count(*) as NRpezzi
from (select * from Catalogo group by Pezzo) C 
where C.Pezzo NOT IN (
							select Pezzo
							from PezziNecessari
						)
GROUP BY C.Categoria
ORDER BY NRpezzi;


select A.Categoria, A.Utilizzati, A.NonUtilizzati, B.NRpezzi AS Totale
from (select A.Categoria, B.NRpezzi AS Utilizzati,  A.NRpezzi NonUtilizzati
from 
(SELECT B.Categoria, NRpezzi
FROM (select C.Categoria, count(*) as NRpezzi
from (select * from Catalogo group by Pezzo) C RIGHT JOIN (select * from Catalogo group by Pezzo) P ON(C.CodicePezzo = P.CodicePezzo)
where C.Pezzo NOT IN (
select Pezzo
from PezziNecessari)
GROUP BY C.Categoria) AS A RIGHT JOIN (select * from Catalogo group by Categoria) AS B 
ON (A.Categoria = B.Categoria)) AS A JOIN (
SELECT A.Categoria, B.NRpezzi
FROM (select * from Catalogo group by Categoria) as A LEFT JOIN
(select C.Categoria, count(*) as NRpezzi
FROM (SELECT * FROM Catalogo GROUP BY Pezzo) C JOIN (SELECT * FROM PezziNecessari GROUP BY Pezzo) P ON (C.Pezzo=P.Pezzo)
GROUP BY C.Categoria) AS B ON (A.Categoria = B.Categoria)) AS B ON (A.Categoria = B.Categoria)) AS A 
JOIN (select a.Categoria, count(*) as NRpezzi
from (select Categoria, Pezzo from Catalogo group by Pezzo) AS A
group by A.Categoria
) AS B ON (A.Categoria = B.Categoria)
ORDER BY A.Categoria;


----------------------------------------------------------------------------------------------------------------------
SELECT B.Categoria, A.NRpezzi
FROM (select C.Categoria, count(*) as NRpezzi
from (select * from Catalogo group by Pezzo) C RIGHT JOIN (select * from Catalogo group by Pezzo) P ON(C.CodicePezzo = P.CodicePezzo)
where C.Pezzo NOT IN (
							select Pezzo
							from PezziNecessari
						)
GROUP BY C.Categoria) AS A RIGHT JOIN (select * from Catalogo group by Categoria) AS B ON (A.Categoria = B.Categoria)
ORDER BY B.Categoria;
-----------------------------------------------------------------------------------------------------------------------
SELECT A.Categoria, B.NRpezzi
FROM (select * from Catalogo group by Categoria) as A LEFT JOIN
(select C.Categoria, count(*) as NRpezzi
FROM (SELECT * FROM Catalogo GROUP BY Pezzo) C JOIN (SELECT * FROM PezziNecessari GROUP BY Pezzo) P ON (C.Pezzo=P.Pezzo)
GROUP BY C.Categoria) AS B ON (A.Categoria = B.Categoria)
ORDER BY A.Categoria;
-------------------------------------------------------------------------------------------------------------------------
select a.Categoria, count(*) as NRpezzi
from (select Categoria, Pezzo from Catalogo group by Pezzo) AS A
group by A.Categoria
ORDER BY A.CATEGORIA;

