       /copy qcpylesrc,vvHspec                                                                                      /inc
      ** --------------------------------------------------------------
      **         Copyright (C) 2008-2018 CNX Corporation
      ** --------------------------------------------------------------
      **     Object ID: EXHTTPGET1
      **       Version: V5.2
      **   Description: Valence Examples - HTTP Get (simple)
      ** --------------------------------------------------------------
      //* Object....: SRGDtaPull
      //* Purpose...: Pull the SRG payroll data from the website
      //*
      //* Author....: Virginia Klein
      //* Date......: 05-27-2019
      //*
      //*--------------------------------------------------------------------------------
      //* Modifications:
      //* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      //* Proj#    Date      Init  Description
      //* -----   ---------- ----  -----------
      //*
      //*
      //*--------------------------------------------------------------------------------
      //* CRTPGM PGM(WSCLIB/SRGDtaPull) MODULE(WSCLIB/SRGDtaPull)
      //*  BNDSRVPGM((*libl/VVSRVPGM) (*libl/JSON))

      /define nabButton
      /include qcpylesrc,vvNabTmpl
       // --------------------------------------------------
       // Prototype for procedure: queryAndInsertData
       // --------------------------------------------------
       DCL-PR queryAndInsertData ind;
         startDate date const;
       END-PR ;


       Dcl-PR clearSRGPayImp ind;
       End-PR ;


       Dcl-PR loadSRGINDFile extpgm('SRGDTAMAP');
         status char(1);
       End-PR ;



       dcl-s gStatus     char(1)  inz('A') ;
       dcl-s inDate      date;
       dcl-s isOK        ind      inz(*on);


         inDate = vvIn_date('WEDATE');

         isOK =   clearSRGPayImp();

         If isOK;
           isOk = queryandInsertData(inDate);
         EndIf;


         If isOK;
           loadSRGINDFile(gstatus);
         EndIf;


         If isOK;
           vvOut_toJsonPair('success:true,info:File Successfully Imported');
         Else;
           vvOut_toJsonPair('success:false,info:Unable to Import');
         EndIf;


       *inlr = *on;

       // --------------------------------------------------
       // Procedure name: clearSRGPayImp
       // Purpose:        clear the workfile,  srgpayimp
       // Returns:
       // Parameter:
       // --------------------------------------------------

       Dcl-Proc clearSRGPayImp;
         Dcl-PI *N IND;
         End-PI;

         dcl-s isOK        ind      inz(*on);

         Exec Sql
              Delete from SRGPAYIMP;

         If  sqlCode <> 0 and  sqlCode <> 100;
           isOK = *off;
         EndIf;

         return isOK;

       End-Proc clearsrgPayImp;


       // --------------------------------------------------
       // Procedure name: queryAndInsertData
       // Purpose:        query for the data and insert it into srgpayimp
       // Returns:
       // Parameter:      startDate
       // --------------------------------------------------
       DCL-PROC queryAndInsertData ;
         DCL-PI *N ind;
           startDate DATE CONST;
         END-PI ;

         dcl-s sqlstmt   char(1000);
         dcl-s isOK      ind  inz(*on);


         sqlstmt =
         'insert into srgpayimp +
         (idx, cono, ptype, paydate, empname, empno, +
                       job_number, hrswrk, rate, amount) +
          select idx, 22,  ptype, +
            DATE(TO_DATE(paydate, ''MM/DD/YYYY'')) as paydate, +
            displayName as empname, ifnull(EmployeeNumber,'' '' ) as empno, +
            JobNumber as job_number, +
            ifnull(hours, 0) as hrswrk, +
            ifnull(Rate, 0) as rate, ifnull(amount, 0) as amount +
          from JSON_TABLE(''{"root": ''  +
          concat httpgetclob(''https://matrix.srgi.ca/DesktopModules+
              /WebApiSpectrum/API/Tally/PayrollExportPerDay?StartDate=' +
            %char(startDate) +''', '''') concat ''}'', ''$.root[*]'' +
            COLUMNS(Idx int PATH ''$.Index'',  +
            pType varchar(25) PATH ''$.Type'',  +
            payDate char(10) PATH ''$.Date'',  +
            DisplayName varchar(25) PATH ''$.DisplayName'',  +
            EmployeeNumber varchar(8) PATH ''$.EmployeeNumber'',  +
            JobNumber varchar(4) PATH ''$.JobNumber'',  +
            Hours dec(5,2) PATH ''$.Hours'',  +
            Rate  dec(5,2) PATH ''$.Rate'',  +
            Amount  dec(5,2) PATH ''$.Amount''  +
           )) AS X';

          Exec SQL
            execute immediate :sqlstmt;


         If sqlCode <> 0;
           isOK = *off;
         EndIf;

         return isOK;
       END-PROC ;
      /include qcpylesrc,vvNabTmpl

