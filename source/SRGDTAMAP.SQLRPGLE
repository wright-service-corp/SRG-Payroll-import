**Free

Ctl-Opt Option(*Srcstmt: *Nodebugio);
/copy cpysrc,NTMod01pr
/copy cpysrc,NTMod04pr
//**************************************************************************
//* Write batch records from SRGPAYIMP into SRGPRTIND
//* Written  : April 30, 2019
//* Developer: Mallik R. Tapepta
//*-------------------------------------------------------------------------
//* Modifications:
//* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
//* Mod Date     By    Modification Summary
//* --- -------- ---   -----------------------------------------------------
//*   1 05-14-19 Bill  Pay Type = Production, remove adjusted amount
//*
//**************************************************************************
//copy cpysrc,ntoututpr
//
// --------------------------------------------------
// Prototype for procedure: Main
// --------------------------------------------------
Dcl-PI *N;
  sStatus   CHAR(1);
End-PI ;
//
// Global Variables
//
Dcl-S iStatus    char( 1 );
//
// Null Indicators
//
dcl-s Nullindsi  int(5) Dim(30);
dcl-s NullValuei Like(NullIndsi) Inz(-1);
dcl-s Nullindsp  int(5) Dim(81);
dcl-s NullValuep Like(NullIndsp) Inz(-1);

//
// Data Received from SRG
//
Dcl-Ds InDs
  Extname('SRGPAYIMP') Qualified
End-Ds;

//
// CGC Payroll TimeCard Import integration
//
Dcl-Ds OutDs
  Extname('SRGPRTIND') Qualified Inz
End-Ds;


Dcl-DS JCTKDs Qualified;
  CompNo   Packed(2:0);
  DivNo    Packed(3:0);
  Job      Char(6);
END-DS;

// - - - - - - - - - - - - - - - - - - - - - - -
// MainLine Start
// - - - - - - - - - - - - - - - - - - - - - - -

iStatus = sStatus;

prepareSRGPayImpDataToProcess();

Exec Sql
  Fetch Next From iCursor
  Into :InDs;

Dow SqlCode = *Zero;

  pushPayroll();

  Exec Sql
    Fetch Next From iCursor
     Into :InDs;

EndDo;

Exec Sql
  Close Icursor;

*INLR = *ON;

Return;

//--------------------------------------------------------------------
// Procedure name: prepareSRGPayImpDataToProcess
// Purpose:        Prepare SRGPAYIMP data to process
// Returns:        None
// Parameter:      None
//--------------------------------------------------------------------
Dcl-Proc prepareSRGPayImpDataToProcess;

Exec Sql
  Delete from SRGPRTIND;

Exec Sql
  Declare iCursor Cursor For
  Select *
    From SRGPAYIMP
   Where STATUS = :iStatus
   Order By OCCONO, OCDVNO, PAYDATE
;

Exec Sql
  Open iCursor;

End-Proc ;

//--------------------------------------------------------------------
// Procedure name: pushPayroll
// Purpose:        Populate the Payroll TimeCard Import DS
// Returns:        None
// Parameter:      None
//--------------------------------------------------------------------
Dcl-Proc  pushPayroll;

  Dcl-s Wrk_Date   Packed(8:0);
  Dcl-s wrk_JobSub Char(9)    ;

  // Payroll Import

  Clear OutDs;

  OutDs.INSTAT  = InDs.STATUS ;
  OutDs.INCONO  = InDs.OCCONO ;
  OutDs.INDVNO  = InDs.OCDVNO ;
  OutDs.EMPNAME = InDs.EMPNAME;
  OutDs.SRGEMPNO= InDs.EMPNO  ;
  OutDs.INEENO  = getSRGAltEmpNumber(InDs.OCCONO
                                       :InDs.OCDVNO
                                       :InDs.EMPNO);
  OutDs.INGP05  = OutDs.INEENO    ;
  OutDs.INSQ05  = getNextPrtSeqNumber(
                        OutDs.INCONO
                       :OutDs.INDVNO
                       :OutDs.INLEEN
                       :OutDs.INGP05) + 1;
  OutDs.INDYWK  = getSRGDayOfWeek(InDs.PAYDATE:'*ISO ') ;
  wrk_Date      = %Dec(InDs.PAYDATE:*ISO);
  OutDs.INWKNO  = getWeekNumFromGLTWEEK(
                        OutDs.INCONO
                       :OutDs.INDVNO
                       :wrk_Date);

  OutDs.INEECL  = getEmpClass(InDs.OCCONO
                                :InDs.OCDVNO
                                :OutDs.INEENO);
  OutDs.INEETY  = getEmpType (InDs.OCCONO
                                :InDs.OCDVNO
                                :OutDs.INEENO);
  wrk_JobSub    = getSRGAltJobSub(InDs.OCCONO
                                    :InDs.OCDVNO
                                    :InDs.JOB_NUMBER);
  OutDs.INJBNO  = %Subst(wrk_JobSub:1:6);
  OutDs.INSJNO  = %Subst(wrk_JobSub:7:3);
  OutDs.INPYTY  = %Char(InDs.IDX);
  JCTKDs.CompNo = InDs.OCCONO ;
  JCTKDs.DivNo  = InDs.OCDVNO ;
  JCTKDs.Job    = OutDs.INJBNO    ;
  OutDs.INCUST  = getJCTDSCCustomerNumber(JCTKDS);
  OutDs.INDTWE  = getSRGWeekEndIngDate(InDs.PAYDATE:'*ISO ') ;
  OutDs.INCNWO  = %Char(InDs.SRGPAYID);
  // OutDs.INBTNO  = FLDDTADs.BATCHNO ;

  setCostAdjCodeTypeDed();

  OutDs.INLEEN  = *Zero ;
  OutDs.INEECO  = InDs.OCCONO ;
  OutDs.INEEDV  = InDs.OCDVNO ;
  OutDs.INDICO  = InDs.OCCONO ;

  // Payroll import load
  Exec Sql
    Insert into SRGPRTIND Values(:OutDs);

End-Proc ;

//--------------------------------------------------------------------
// Procedure name: getSRGAltEmpNumber
// Purpose:        Retrieve SRG Alt.Employee Number
// Returns:        SRG's Alt. Employee Number
// Parameter:      SRG EMPNO
//--------------------------------------------------------------------
dcl-proc getSRGAltEmpNumber Export;
  dcl-pi *N  Packed(9:0);
    SRG_CompNo Packed(2:0) ;
    SRG_DivNo  Packed(3:0) ;
    SRG_EmpNo  Char(10) ;
  end-pi;

  Dcl-s UDCat       Char(10) Inz('OTHER EE#');
  Dcl-s rcv_AltEmp# Packed(9:0);
  Dcl-s rtn_AltEmp# Packed(9:0);
  dcl-c Successful  00000;

  Exec Sql
    Select VFEENO into :rcv_AltEmp#
      from SYTUPRMST
     Where VFSBCT = :UDCat
       and VFCONO = :SRG_CompNo
       and VFDVNO = :SRG_DivNo
       and Substr(VF10A1, 1, 4) = Substr(:SRG_EmpNo, 1, 4);

    If SQLCOD = Successful;
      rtn_AltEmp# = rcv_AltEmp#;
    Else;
      rtn_AltEmp# = *Zero ;
    Endif;

  Return rtn_AltEmp# ;

end-proc ;

//--------------------------------------------------------------------
// Procedure name: getSRGAltJobNumber
// Purpose:        Retrieve SRG Alt.Job Number
// Returns:        SRG's Alt. Job Number
// Parameter:      SRG JobNO
//--------------------------------------------------------------------
dcl-proc getSRGAltJobSub Export;
 dcl-pi *N    Char(9) ;
   SRG_CompNo Packed(2:0) ;
   SRG_DivNo  Packed(3:0) ;
   SRG_JobSub   Char(6)   ;
  end-pi;

  Dcl-s UDCat       Char(10) Inz('ALT JOB#');
  Dcl-s rcv_JobSub  Char(9);
  Dcl-s rtn_JobSub  Char(9);
  dcl-c Successful    00000;

  Exec Sql
    Select VFJBNO || VFSJNO into :rcv_JobSub
      from SYTUJCDSC
     Where VFSBCT = :UDCat
       and VFCONO = :SRG_CompNo
       and VFDVNO = :SRG_DivNo
       and VF10A2 = :SRG_JobSub;

    If SQLCOD = Successful;
      rtn_JobSub = rcv_JobSub ;
    Else;
      rtn_JobSub = *Blanks    ;
    Endif;

  Return rtn_JobSub ;

end-proc ;

//--------------------------------------------------------------------
// Procedure name: getSRGDayOfWeek
// Purpose:        Retrieve SRG's Day of week (Starts with Friday)
// Returns:        SRG's Day of week
// Parameter:      Date
//--------------------------------------------------------------------
dcl-proc getSRGDayOfWeek Export;
 dcl-pi *N   Zoned(1:0);
   Wrk_Date  Date     Const;
   Wrk_Fomat Char(4)  Const;
  end-pi;

  dcl-s Wk_Date        Date(*ISO);
  dcl-s wrk_DayofWeek  Zoned(1:0);
  dcl-s rtn_SRGDOWk    Zoned(1:0);

  Wk_Date = Wrk_Date;

  wrk_DayOfWeek = getDayOfWeek(Wrk_Date:Wrk_Fomat);
  If wrk_DayOfWeek < 6;
    wrk_DayOfWeek += 2;
  Else;
    wrk_DayOfWeek -= 5;
  ENDIF;

  rtn_SRGDOWK = wrk_DayOfWeek;

  Return rtn_SRGDOWk ;

end-proc ;

//--------------------------------------------------------------------
// Procedure name: getSRGWeekEndingDate
// Purpose:        Retrieve SRG's Weekending date (Thursday)
// Returns:        SRG's Weekending date
// Parameter:      Date
//--------------------------------------------------------------------
dcl-proc getSRGWeekEndingDate Export;
  dcl-pi *N   Date(*ISO);
    Wrk_Date  Date    Const;
    Wrk_Fomat Char(4) Const;
  end-pi;

  dcl-s Wk_Date       Date(*ISO);
  dcl-s rtn_SRGWEDT   Date(*ISO);
  dcl-s SRGDayOfWk    Int(3);

  Wk_Date = Wrk_Date;
  SRGDayOfWk = getSRGDayOfWeek(wrk_Date:'*ISO ') ;

  If SRGDayOfWk <> 7;
     SRGDayOfWk = 7 - SRGDayOfWk;
     Wk_Date = Wk_Date + %Days(SRGDayOfWk);
  ENDIF;

  rtn_SRGWEDT = wk_Date;

  Return rtn_SRGWEDT ;

end-proc ;

//--------------------------------------------------------------------
// Procedure name: getEmpClass
// Purpose:        To get employee class
// Returns:        Employee Class
// Parameter:      Company
//                 Division
//                 Employee No
//--------------------------------------------------------------------
dcl-proc getEmpClass Export;
  Dcl-PI *n Packed(3:0);
    iCompNo Packed(2:0);
    iDivNo  Packed(3:0);
    iEmpNo  BinDec(9:0);
  End-PI;

  Dcl-s rcv_EmpCls Packed(3:0);
  Dcl-s rtn_EmpCls Packed(3:0);
  dcl-c Successful       00000;

  Exec Sql
       Select EMEECL
         into :rcv_EmpCls
         from HRTEMP
        Where EMEECO = :iCompNo
          and EMEEDV = :iDivNo
          and EMEENO = :iEmpNo;

  If SQLCOD = Successful;
    rtn_EmpCls = rcv_EmpCls;
  Else;
    rtn_EmpCls = *Zero;
  ENDIF;

  Return rtn_Empcls;

end-proc ;

//--------------------------------------------------------------------
// Procedure name: getEmpType
// Purpose:        To get employee type
// Returns:        Employee Type
// Parameter:      Company
//                 Division
//                 Employee No
//--------------------------------------------------------------------
dcl-proc getEmpType Export;
  Dcl-PI *n Char(2);
    iCompNo Packed(2:0);
    iDivNo  Packed(3:0);
    iEmpNo  BinDec(9:0);
  End-PI;

  Dcl-s rcv_EmpTyp Char(2);
  Dcl-s rtn_EmpTyp Char(2);
  dcl-c Successful   00000;

  Exec Sql
       Select EMEETY
         into :rcv_EmpTyp
         from HRTEMP
        Where EMEECO = :iCompNo
          and EMEEDV = :iDivNo
          and EMEENO = :iEmpNo;

  If SQLCOD = Successful;
    rtn_EmpTyp = rcv_EmpTyp;
  Else;
    rtn_EmpTyp = *Blanks;
  ENDIF;

  Return rtn_EmpTyp;

end-proc ;

//------------------------------------------------------------------------
// Procedure name: getJCTDSCCustomerNumber
// Purpose:        To get the Customer number for the given key in JCTDSC
// Returns:        Customer Number
//------------------------------------------------------------------------
Dcl-Proc getJCTDSCCustomerNumber Export;
  Dcl-PI *n Packed(5:0);
    JCT LikeDs(JCTKds);
  End-PI;

  dcl-c Successful  00000;
  Dcl-s rcvCust     Packed(5:0);
  Dcl-s rtnCust     Packed(5:0);

  Exec Sql Select GCUST
             into :rcvCust
             from JCTDSC
            Where (GCONO = :JCT.CompNo
              and  GDVNO = :JCT.DivNo
              and  GJBNO = :JCT.Job
                  )
           ;
  If SqlCod = Successful;
     rtnCust = rcvCust ;
  Else;
     rtnCust = *Zero;
  Endif;

  Return rtnCust;

END-PROC ;

//--------------------------------------------------------------
// Procedure name: getNextPrtSeqNumber
// Purpose:        Return the higest sequence number in PRTIND
// Returns:        Highest Sequence number
// Parameter:      Company, Division, Employee and Group
//--------------------------------------------------------------
dcl-proc getNextPrtSeqNumber Export;
  dcl-Pi *N Packed(5:0);
    Wrk_Co  Packed(2:0) Const;
    Wrk_Dv  Packed(3:0) Const;
    Wrk_Emp Packed(9:0) Const;
    Wrk_Grp Packed(9:0) Const;
  END-PI;

  dcl-s MaxSeq Packed(5:0);

    Exec Sql
     Select Max(Insq05) into :MaxSeq :NullIndsp
      From SRGPRTInd
         Where
          IncoNo = :Wrk_Co  and
          InDvNo = :Wrk_Dv  and
          InLeen = :Wrk_Emp and
          InGp05 = :Wrk_Grp;

   If SqlCode = *Zero;
      Return MaxSeq;
   Else;
      Return *Zero;
   EndIf;

End-Proc ;

//--------------------------------------------------------------
// Procedure name: setCostCodeAdjTypeDed
// Purpose:        Set Costcode, Cost type, Adj type, Deduct No
// Returns:        None
// Parameter:      None
//
// NOTE: Below hard coded values are not replaced with
//       variables as too many variable need to be added
//       for various data values in each case in Select.
//--------------------------------------------------------------
dcl-proc setCostAdjCodeTypeDed Export;

  Select;
  When InDs.IDX = 1;
    OutDs.INRGHR  = InDs.HRSWRK ;
    OutDs.INRGRT  = InDs.RATE ;
    // OutDs.INAA01  = OutDs.INRGHR * OutDs.INRGRT ;
    If OutDs.INJBNO <> *Blanks;
      OutDs.INJCDI  = '01 01    01 ' ;
      OutDs.INCSTY  = 'L' ;
    ENDIF;
  When InDs.IDX = 2;
    OutDs.INAJ01  = 'NT' ;
    OutDs.INDN01  =  21  ;
    If OutDs.INJBNO <> *Blanks;
      OutDs.INJCDI  = '01 01    09 ' ;
      OutDs.INCSTY  = 'M' ;
    ENDIF;
    OutDs.INAA01  = InDs.AMOUNT ;
  When InDs.IDX = 3;
    OutDs.INAJ01  = 'OD' ;
    OutDs.INDN01  =  26  ;
    If OutDs.INJBNO <> *Blanks;
      OutDs.INJCDI  = '01 01    10 ' ;
      OutDs.INCSTY  = 'M' ;
    ENDIF;
    OutDs.INAA01  = InDs.AMOUNT ;
  When InDs.IDX = 4;
    OutDs.INAJ01  = 'NT' ;
    OutDs.INDN01  =  23  ;
    If OutDs.INJBNO <> *Blanks;
      OutDs.INJCDI  = '01 01    07 ' ;
      OutDs.INCSTY  = 'M' ;
    ENDIF;
    OutDs.INAA01  = InDs.AMOUNT ;
  When InDs.IDX = 5;
    OutDs.INAJ01  = 'NT' ;
    OutDs.INDN01  =  22  ;
    If OutDs.INJBNO <> *Blanks;
      OutDs.INJCDI  = '01 01    08 ' ;
      OutDs.INCSTY  = 'M' ;
    ENDIF;
    OutDs.INAA01  = InDs.AMOUNT ;
  Endsl;

END-PROC;

