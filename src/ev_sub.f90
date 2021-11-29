!
! Copyright (C) 2003-2013 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-----------------------------------------------------------------------
SUBROUTINE ev_sub(vmin,b0,b01,b02,emin_out,inputfile)
!-----------------------------------------------------------------------
!
!      fit of E(v) or H(V) at finite pressure to an equation of state (EOS)
!
!      Interactive input:
!         au or Ang
!         structure
!         equation of state
!         input data file
!         output data file
!
!      Input data file format for cubic systems:
!         a0(1)  Etot(1)
!         ...
!         a0(n)  Etot(n)
!      where a0 is the lattice parameter (a.u. or Ang)
!      Input data file format for noncubic (e.g. hexagonal) systems:
!         V0(1)  Etot(1)
!         ...
!         V0(n)  Etot(n)
!      where V0 is the unit-cell volume (a.u.^3 or Ang^3)
!      e.g. for an hexagonal cell,
!         V0(i)  = sqrt(3)/2 * a^2 * c    unit-cell volume
!         Etot(i)= min Etot(c)   for the given volume V0(i)
!      Etot in atomic (Rydberg) units
!
!      Output data file format  for cubic systems:
!      # a0=... a.u., K0=... kbar, dk0=..., d2k0=... kbar^-1, Emin=... Ry
!      # a0=... Ang,  K0=... GPa , V0=... (a.u.)^3, V0 = Ang^3
!         a0(1)  Etot(1) Efit(1)  Etot(1)-Efit(1)  Pfit(1)  Enth(1)
!         ...
!         a0(n)  Etot(n) Efit(n)  Etot(n)-Efit(n)  Pfit(n)  Enth(n)
!      Output data file format  for noncubic systems:
!      # V0=...(a.u.)^3, K0=... kbar, dk0=..., d2k0=... kbar^-1, Emin=... Ry
!      # V0=...Ang^3,  K0=... GPa
!         V0(1)  Etot(1) Efit(1)  Etot(1)-Efit(1)  Pfit(1)  Enth(1)
!         ...
!         V0(n)  Etot(n) Efit(n)  Etot(n)-Efit(n)  Pfit(n)  Enth(n)
!      where
!            a0(i), V0(i), Etot(i) as in input
!            Efit(i) is the fitted value from the EOS
!            Pfit(i) is the corresponding pressure from the EOS (GPa)
!            Enth(i)=Efit(i)+Pfit(i)*V0(i) is the enthalpy (Ry)
!!
      USE kinds, ONLY: DP
      USE constants, ONLY: bohr_radius_angs, ry_kbar
      USE ev_xml,    ONLY : write_evdata_xml
      USE control_pressure, ONLY : pressure_kb
      USE mp,        ONLY : mp_bcast
      USE io_global, ONLY : ionode, ionode_id, stdout
      USE mp_images, ONLY : my_image_id, root_image, intra_image_comm

      IMPLICIT NONE
      REAL(DP), INTENT(OUT)  :: vmin, b0, b01, b02, emin_out
      CHARACTER(LEN=*) :: inputfile
      INTEGER, PARAMETER:: nmaxpar=4, nmaxpt=100, nseek=10000, nmin=8
      INTEGER :: npar,npt,ieos, ierr
      CHARACTER :: bravais*3, au_unit*3, filin*256
      REAL(DP) :: par(nmaxpar), deltapar(nmaxpar), parmin(nmaxpar), &
             parmax(nmaxpar), v0(nmaxpt), etot(nmaxpt), efit(nmaxpt), &
             fac, emin, chisq, a
      REAL(DP), PARAMETER :: gpa_kbar = 10.0_dp
      LOGICAL :: in_angstrom
      INTEGER :: iu_ev
      INTEGER :: find_free_unit
      CHARACTER(LEN=256) :: fileout
  !
  IF (my_image_id /= root_image) RETURN

  IF ( ionode ) THEN

      iu_ev=find_free_unit()
      OPEN(UNIT=iu_ev, FILE=TRIM(inputfile), STATUS='OLD', FORM='FORMATTED')

      READ(iu_ev,'(a)') au_unit
      in_angstrom = au_unit=='Ang' .or. au_unit=='ANG' .or. &
                    au_unit=='ang'
      READ(iu_ev, '(a)') bravais
!
      IF(bravais=='fcc'.or.bravais=='FCC') THEN
         fac = 0.25d0
      ELSEIF(bravais=='bcc'.or.bravais=='BCC') THEN
         fac = 0.50d0
      ELSEIF(bravais=='sc'.or.bravais=='SC') THEN
         fac = 1.0d0
      ELSEIF(bravais=='noncubic'.or.bravais=='NONCUBIC' .or.  &
             bravais=='hex'.or.bravais=='HEX' ) THEN
!         fac = sqrt(3d0)/2d0 ! not used
         fac = 0.0_DP ! not used
      ELSE
         CALL errore('ev_sub','ev: unexpected lattice '//TRIM(bravais), 1)
      ENDIF
!
      READ (iu_ev,*) ieos
      IF(ieos==1 .or. ieos==4) THEN
         npar=3
      ELSEIF(ieos==2 .or. ieos==3) THEN
         npar=4
      ELSE
         CALL errore('ev_sub', 'Unexpected eq. of state', ieos)
      ENDIF
      READ(iu_ev, '(a)') filin
      READ(iu_ev, '(a)') fileout

      CLOSE(iu_ev)
!
!  reading the data
!
      OPEN(unit=iu_ev,file=TRIM(filin),status='old',form='formatted',iostat=ierr)
      IF (ierr/=0) THEN
         ierr= 1 
         GO TO 99
      END IF
  10  CONTINUE
      emin=1d10
      DO npt=1,nmaxpt
         IF (bravais=='noncubic'.or.bravais=='NONCUBIC' .or. &
             bravais=='hex'.or.bravais=='HEX' ) THEN
            READ(iu_ev,*,err=10,END=20) v0(npt), etot(npt)
            IF (in_angstrom) v0(npt)=v0(npt)/bohr_radius_angs**3
         ELSE
            READ(iu_ev,*,err=10,END=20) a, etot(npt)
            IF (in_angstrom) a = a/bohr_radius_angs
            v0  (npt) = fac*a**3
         ENDIF
         IF(etot(npt)<emin) THEN
            par(1) = v0(npt)
            emin = etot(npt)
         ENDIF
      ENDDO
      npt = nmaxpt+1
  20  CLOSE(iu_ev)
      npt = npt-1
!
! par(1) = V, Volume of the unit cell in (a.u.^3)
! par(2) = B, Bulk Modulus (in KBar)
! par(3) = dB/dP (adimensional)
! par(4) = d^2B/dP^2 (in KBar^(-1), used only by 2nd order formulae)
!
      par(2) = 500.0d0
      par(3) = 5.0d0
      par(4) = -0.01d0
!
      parmin(1) = 0.0d0
      parmin(2) = 0.0d0
      parmin(3) = 1.0d0
      parmin(4) = -1.0d0
!
      parmax(1) = 100000.d0
      parmax(2) = 100000.d0
      parmax(3) = 15.0d0
      parmax(4) = 0.0d0
!
      deltapar(1) = 0.1d0
      deltapar(2) = 100.d0
      deltapar(3) = 1.0d0
      deltapar(4) = 0.01d0
!
!      CALL find_minimum &
!           (npar,par,deltapar,parmin,parmax,nseek,nmin,chisq)
      CALL find_minimum (npar,par,chisq)
!
      CALL write_results &
           (npt,in_angstrom,fac,v0,etot,efit,ieos,par,npar,emin,chisq, &
            fileout)
!
      CALL write_evdata_xml  &
           (npt,fac,v0,etot,efit,ieos,par,npar,emin,pressure_kb,&
                                                        chisq,fileout, ierr)

      IF (ierr /= 0) GO TO 99
    ENDIF
99  CALL mp_bcast ( ierr, ionode_id, intra_image_comm )
    IF ( ierr == 1) THEN
       CALL errore( 'ev_sub', 'file '//trim(filin)//' cannot be opened', ierr )
    ELSE IF ( ierr == 2 ) THEN
       CALL errore( 'ev_sub', 'file '//trim(fileout)//' cannot be opened', ierr )
    ELSE IF ( ierr == 11 ) THEN
       CALL errore( 'ev_sub', 'no free units to write ', ierr )
    ELSE IF ( ierr == 12 ) THEN
       CALL errore( 'ev_sub', 'error opening the xml file ', ierr )
    ENDIF
    CALL mp_bcast(par, ionode_id, intra_image_comm)
    CALL mp_bcast(emin, ionode_id, intra_image_comm)
    
    vmin=par(1)
    b0=par(2)
    b01=par(3)
    b02=par(4)
    emin_out=emin

    RETURN

    CONTAINS
!
!-----------------------------------------------------------------------
      SUBROUTINE eqstate(npar,par,chisq,ediff)
!-----------------------------------------------------------------------
!
      IMPLICIT NONE
      INTEGER, INTENT(in) :: npar
      REAL(DP), INTENT(in) :: par(npar)
      REAL(DP), INTENT(out):: chisq
      REAL(DP), OPTIONAL, INTENT(out):: ediff(npt)
      INTEGER :: i
      REAL(DP) :: k0, dk0, d2k0, c0, c1, x, vol0, ddk
!
      vol0 = par(1)
      k0   = par(2)/ry_kbar ! converts k0 to Ry atomic units...
      dk0  = par(3)
      d2k0 = par(4)*ry_kbar ! and d2k0/dp2 to (Ry a.u.)^(-1)
!
      IF(ieos==1.or.ieos==2) THEN
         IF(ieos==1) THEN
           c0 = 0.0d0
         ELSE
           c0 = ( 9.d0*k0*d2k0 + 9.d0*dk0**2-63.d0*dk0+143.d0 )/48.d0
         ENDIF
         c1 = 3.d0*(dk0-4.d0)/8.d0
         DO i=1,npt
            x = vol0/v0(i)
            efit(i) = 9.d0*k0*vol0*( (-0.5d0+c1-c0)*x**(2.d0/3.d0)/2.d0 &
                         +( 0.50-2.d0*c1+3.d0*c0)*x**(4.d0/3.d0)/4.d0 &
                         +(       c1-3.d0*c0)*x**(6.d0/3.d0)/6.d0 &
                         +(            c0)*x**(8.d0/3.d0)/8.d0 &
                         -(-1.d0/8.d0+c1/6.d0-c0/8.d0) )
         ENDDO
      ELSE
         IF(ieos==3) THEN
            ddk = dk0 + k0*d2k0/dk0
         ELSE
            ddk = dk0
         ENDIF
         DO i=1,npt
            efit(i) = - k0*dk0/ddk*vol0/(ddk-1.d0) &
            + v0(i)*k0*dk0/ddk**2*( (vol0/v0(i))**ddk/(ddk-1.d0)+1.d0) &
            - k0*(dk0-ddk)/ddk*( v0(i)*log(vol0/v0(i)) + v0(i)-vol0 )
         ENDDO
      ENDIF
!
!      emin = equilibrium energy obtained by minimizing chi**2
!
      emin = 0.0d0
      DO i = 1,npt
         emin = emin + etot(i)-efit(i)
      ENDDO
      emin = emin/npt
!
      chisq = 0.0d0
      DO i = 1,npt
          efit(i) = efit(i)+emin
          chisq   = chisq + (etot(i)-efit(i))**2
          IF(present(ediff)) ediff(i) = efit(i)-etot(i)
       ENDDO
      chisq = chisq/npt
!
      RETURN
    END SUBROUTINE eqstate

!
!-----------------------------------------------------------------------
      SUBROUTINE write_results &
            (npt,in_angstrom,fac,v0,etot,efit,istat,par,npar,emin,chisq, &
             filout)
!-----------------------------------------------------------------------
!
      USE control_pressure, ONLY : pressure_kb, pressure
      IMPLICIT NONE
      INTEGER, INTENT(in) :: npt, istat, npar
      REAL(DP), INTENT(in):: v0(npt), etot(npt), efit(npt), emin, chisq, fac
      REAL(DP), INTENT(inout):: par(npar)
      REAL(DP), EXTERNAL :: keane, birch
      LOGICAL, INTENT(in) :: in_angstrom
      CHARACTER(len=256), intent(in) :: filout
      !
      REAL(DP) :: p(npt), epv(npt)
      INTEGER :: i, iun
      INTEGER :: find_free_unit
      LOGICAL :: exst

      IF(filout/=' ') THEN
         iun=find_free_unit()
         INQUIRE(file=filout,exist=exst)
         IF (exst) PRINT '(5x,"Beware: file ",A," will be overwritten")',&
                  trim(filout)
         OPEN(unit=iun,file=filout,form='formatted',status='unknown', &
              iostat=ierr)
         IF (ierr/=0) THEN
            ierr= 2 
            GO TO 99
         END IF
      ELSE
         iun=6
      ENDIF

      IF(istat==1) THEN
         WRITE(iun,'("# equation of state: birch 1st order.  chisq = ", &
                   & d10.4)') chisq
      ELSEIF(istat==2) THEN
         WRITE(iun,'("# equation of state: birch 3rd order.  chisq = ", &
                   & d10.4)') chisq
      ELSEIF(istat==3) THEN
         WRITE(iun,'("# equation of state: keane.            chisq = ", &
                   & d10.4)') chisq
      ELSEIF(istat==4) THEN
         WRITE(iun,'("# equation of state: murnaghan.        chisq = ", &
                   & d10.4)') chisq
      ENDIF

      IF(istat==1 .or. istat==4) par(4) = 0.0d0

      IF(istat==1 .or. istat==2) THEN
         DO i=1,npt
            p(i)=birch(v0(i)/par(1),par(2),par(3),par(4))
         ENDDO
      ELSE
         DO i=1,npt
            p(i)=keane(v0(i)/par(1),par(2),par(3),par(4))
         ENDDO
      ENDIF

      DO i=1,npt
         epv(i) = etot(i) + p(i)*v0(i) / ry_kbar
      ENDDO

      IF ( fac /= 0.0_dp ) THEN
! cubic case
         IF (pressure_kb /= 0.0_DP) THEN
            WRITE(iun,'("# a0 =",f8.4," a.u., k0 =",i5," kbar, dk0 =", &
                    &f6.2," d2k0 =",f7.3," Hmin =",f11.5)') &
                  (par(1)/fac)**(1d0/3d0), int(par(2)), par(3), par(4), emin

         ELSE
            WRITE(iun,'("# a0 =",f8.4," a.u., k0 =",i5," kbar, dk0 =", &
                    &f6.2," d2k0 =",f7.3," emin =",f11.5)') &
                  (par(1)/fac)**(1d0/3d0), int(par(2)), par(3), par(4), emin
         ENDIF
         WRITE(iun,'("# a0 =",f9.5," Ang, k0 =", f6.1," GPa,  V0 = ", &
                  & f7.3," (a.u.)^3,  V0 =", f7.3," A^3 ",/)') &
           & (par(1)/fac)**(1d0/3d0)*bohr_radius_angs, par(2)/gpa_kbar, &
             par(1), par(1)*bohr_radius_angs**3

        WRITE(iun,'(73("#"))')
        IF (pressure_kb /= 0.0_DP) THEN
           WRITE(iun,'("# Lat.Par", 4x, "(E+pV)_calc", 2x, "(E+pV)_fit", 3x, &
             & "(E+pV)_diff", 2x, "Pressure", 6x, "Enthalpy")')
        ELSE
           WRITE(iun,'("# Lat.Par", 7x, "E_calc", 8x, "E_fit", 7x, &
             & "E_diff", 4x, "Pressure", 6x, "Enthalpy")')
        ENDIF
        IF (in_angstrom) THEN
           WRITE(iun,'("# Ang", 13x, "Ry", 11x, "Ry", 12x, &
             & "Ry", 8x, "GPa", 11x, "Ry")')
           WRITE(iun,'(73("#"))')
           WRITE(iun,'(f9.5,2x,f12.5, 2x,f12.5, f12.5, 3x, f8.2, 3x,f12.5)') &
                ( (v0(i)/fac)**(1d0/3d0)*bohr_radius_angs, etot(i), efit(i),  &
                etot(i)-efit(i), (p(i)+pressure_kb)/gpa_kbar, &
                                epv(i), i=1,npt )
        ELSE
           WRITE(iun,'("# a.u.",12x, "Ry", 11x, "Ry", 12x, &
             & "Ry", 8x, "GPa", 11x, "Ry")')
           WRITE(iun,'(73("#"))')
           WRITE(iun,'(f9.5,2x,f12.5, 2x,f12.5, f12.5, 3x, f8.2, 3x,f12.5)') &
                ( (v0(i)/fac)**(1d0/3d0), etot(i), efit(i),  &
                etot(i)-efit(i), (p(i)+pressure_kb)/gpa_kbar,  &
                                  epv(i), i=1,npt )
        ENDIF

      ELSE
! noncubic case
         IF (pressure_kb /= 0.0_DP) THEN
            WRITE(iun,'("# V0 =",f8.2," a.u.^3,  k0 =",i5," kbar,  dk0 =", &
                    & f6.2,"  d2k0 =",f7.3,"  Hmin =",f11.5)') &
                    & par(1), int(par(2)), par(3), par(4), emin
         ELSE
            WRITE(iun,'("# V0 =",f8.2," a.u.^3,  k0 =",i5," kbar,  dk0 =", &
                    & f6.2,"  d2k0 =",f7.3,"  emin =",f11.5)') &
                    & par(1), int(par(2)), par(3), par(4), emin
         ENDIF

         WRITE(iun,'("# V0 =",f8.2,"  Ang^3,  k0 =",f6.1," GPa"/)') &
                    & par(1)*bohr_radius_angs**3, par(2)/gpa_kbar

        WRITE(iun,'(74("#"))')
        IF (pressure_kb /= 0.0_DP) THEN
           WRITE(iun,'("# Vol.", 6x, "(E+pV)_calc", 2x, "(E+pV)_fit", 4x, &
             & "(E+pV)_diff", 2x, "Pressure", 6x, "Enthalpy")')
        ELSE
           WRITE(iun,'("# Vol.", 8x, "E_calc", 8x, "E_fit", 7x, &
             & "E_diff", 4x, "Pressure", 6x, "Enthalpy")')
        ENDIF
        IF (in_angstrom) THEN
          WRITE(iun,'("# Ang^3", 9x, "Ry", 11x, "Ry", 12x, &
             & "Ry", 8x, "GPa", 11x, "Ry")')
          WRITE(iun,'(74("#"))')
          WRITE(iun,'(f8.2,2x,f12.5, 2x,f12.5, f12.5, 3x, f8.2, 3x,f12.5)') &
              ( v0(i)*bohr_radius_angs**3, etot(i), efit(i),  &
               etot(i)-efit(i), (p(i)+pressure_kb)/gpa_kbar, epv(i), i=1,npt )
        else
          WRITE(iun,'("# a.u.^3",8x, "Ry", 11x, "Ry", 12x, &
             & "Ry", 8x, "GPa", 11x, "Ry")')
          WRITE(iun,'(74("#"))')
          WRITE(iun,'(f8.2,2x,f12.5, 2x,f12.5, f12.5, 3x, f8.2, 3x,f12.5)') &
              ( v0(i), etot(i), efit(i),  &
               etot(i)-efit(i), (p(i)+pressure_kb)/gpa_kbar, epv(i), i=1,npt )
        end if

      ENDIF
      IF(filout/=' ') CLOSE(UNIT=iun)
 99   RETURN
    END SUBROUTINE write_results

    SUBROUTINE EOSDIFF(m_, n_, par_, f_, i_)
       IMPLICIT NONE
       INTEGER, INTENT(in)  :: m_, n_
       INTEGER, INTENT(inout)   :: i_
       REAL(DP),INTENT(in)    :: par_(n_)
       REAL(DP),INTENT(out)   :: f_(m_)
       REAL(DP) :: chisq_
       !
         CALL eqstate(n_,par_,chisq_, f_)
      END SUBROUTINE


!-----------------------------------------------------------------------
      SUBROUTINE find_minimum(npar,par,chisq)
!-----------------------------------------------------------------------
!
      USE lmdif_module, ONLY : lmdif0
      IMPLICIT NONE
      INTEGER ,INTENT(in)  :: npar
      REAL(DP),INTENT(out) :: par(nmaxpar)
      REAL(DP),INTENT(out) :: chisq
      !
      REAL(DP) :: vchisq(npar)
      REAL(DP) :: ediff(npt)
      INTEGER :: i
      !
      par(1) = v0(npt/2)
      par(2) = 500.0d0
      par(3) = 5.0d0
      par(4) = -0.01d0 ! unused for some eos
      !      
      CALL lmdif0(EOSDIFF, npt, npar, par, ediff, 1.d-12, i)
      !
      IF(i>0 .and. i<5) THEN
!         PRINT*, "Minimization succeeded"
      ELSEIF(i>=5) THEN
         CALL errore("find_minimum", "Minimization stopped before convergence",1)
      ELSEIF(i<=0) THEN 
        CALL errore("find_minimum", "Minimization error", 1)
      ENDIF
      !
      CALL eqstate(npar,par,chisq)

      END SUBROUTINE find_minimum

  END SUBROUTINE ev_sub

      FUNCTION birch(x,k0,dk0,d2k0)
!
      USE kinds, ONLY : DP
      IMPLICIT NONE
      REAL(DP) birch, x, k0,dk0, d2k0
      REAL(DP) c0, c1

      IF(d2k0/=0.d0) THEN
         c0 = (9.d0*k0*d2k0 + 9.d0*dk0**2 - 63.d0*dk0 + 143.d0 )/48.d0
      ELSE
         c0 = 0.0d0
      ENDIF
      c1 = 3.d0*(dk0-4.d0)/8.d0
      birch = 3.d0*k0*( (-0.5d0+  c1-  c0)*x**( -5.d0/3.d0) &
           +( 0.5d0-2.d0*c1+3.0d0*c0)*x**( -7.d0/3.d0) &
           +(       c1-3*c0)*x**( -9.0d0/3d0) &
           +(            c0)*x**(-11.0d0/3d0) )
      RETURN
    END FUNCTION birch
!
      FUNCTION keane(x,k0,dk0,d2k0)
!
      USE kinds, ONLY : DP
      IMPLICIT NONE
      REAL(DP) keane, x, k0, dk0, d2k0, ddk

      ddk = dk0 + k0*d2k0/dk0
      keane = k0*dk0/ddk**2*( x**(-ddk) - 1d0 ) + (dk0-ddk)/ddk*log(x)

      RETURN
    END FUNCTION keane

!-----------------------------------------------------------------------
SUBROUTINE ev_sub_nodisk(vmin,b0,b01,b02,emin_out)
!-----------------------------------------------------------------------
!
!  This routine is similar to ev_sub, but it receives the input data
!  directly from the shared variable without the need to write on
!  disk. It does not write any output.
!  
!  Before calling this routine the user must set in the module control_ev
!  ieos : the equation of state to use
!         1 - Birch-Murnaghan first order
!         2 - Birch-Murnaghan third order
!         3 - Keane
!         4 - Murnaghan
!  npt : the number of points
!  v0(npt)  : the volume for each point
!  e0(npt)  : the energy or enthalpy for each point
!
!  v0 and e0 must be allocated and deallocated by the user of this routine
!
USE kinds, ONLY: DP
USE constants, ONLY: bohr_radius_angs, ry_kbar
USE control_ev, ONLY : ieos, npt, v0, etot => e0
USE mp,        ONLY : mp_bcast
USE io_global, ONLY : ionode, ionode_id, stdout
USE mp_images, ONLY : my_image_id, root_image, intra_image_comm

IMPLICIT NONE
REAL(DP), INTENT(OUT)  :: vmin, b0, b01, b02, emin_out
INTEGER, PARAMETER:: nmaxpar=4, nmaxpt=100, nseek=20000, nmin=8
INTEGER :: npar,ipt,ierr
REAL(DP) :: par(nmaxpar), deltapar(nmaxpar), parmin(nmaxpar), &
            parmax(nmaxpar), efit(nmaxpt), emin, chisq

IF (my_image_id /= root_image) RETURN

IF (ieos==1 .OR. ieos==4) THEN
   npar=3
ELSEIF(ieos==2 .OR. ieos==3) THEN
   npar=4
ELSE
   CALL errore('ev_sub_nodisk', 'Unexpected eq. of state', ieos)
ENDIF
!
!  find emin and the initial guess for the volume
!
emin=1d10
DO ipt=1,npt
   IF (etot(ipt)<emin) THEN
      par(1) = v0(ipt)
      emin = etot(ipt)
   ENDIF
ENDDO
!
! par(1) = V, Volume of the unit cell in (a.u.^3)
! par(2) = B, Bulk Modulus (in KBar)
! par(3) = dB/dP (adimensional)
! par(4) = d^2B/dP^2 (in KBar^(-1), used only by 2nd order formulae)
!
par(2) = 500.0d0
par(3) = 5.0d0
par(4) = -0.01d0
!
parmin(1) = 0.0d0
parmin(2) = 0.0d0
parmin(3) = 1.0d0
parmin(4) = -1.0d0
!
parmax(1) = 100000.d0
parmax(2) = 100000.d0
parmax(3) = 15.0d0
parmax(4) = 0.0d0
!
deltapar(1) = 0.1d0
deltapar(2) = 100.d0
deltapar(3) = 1.0d0
deltapar(4) = 0.01d0
!
!CALL find_minimum (npar,par,deltapar,parmin,parmax,nseek,nmin,chisq)
CALL find_minimum (npar,par,chisq)
!
CALL mp_bcast(par, ionode_id, intra_image_comm)
CALL mp_bcast(emin, ionode_id, intra_image_comm)
    
vmin=par(1)
b0=par(2)
b01=par(3)
b02=par(4)
emin_out=emin

RETURN

CONTAINS
!
!-----------------------------------------------------------------------
      SUBROUTINE eqstate(npar,par,chisq,ediff)
!-----------------------------------------------------------------------
!
      IMPLICIT NONE
      INTEGER, INTENT(in) :: npar
      REAL(DP), INTENT(in) :: par(npar)
      REAL(DP), INTENT(out):: chisq
      REAL(DP), OPTIONAL, INTENT(out):: ediff(npt)
      INTEGER :: i
      REAL(DP) :: k0, dk0, d2k0, c0, c1, x, vol0, ddk
!
      vol0 = par(1)
      k0   = par(2)/ry_kbar ! converts k0 to Ry atomic units...
      dk0  = par(3)
      d2k0 = par(4)*ry_kbar ! and d2k0/dp2 to (Ry a.u.)^(-1)
!
      IF(ieos==1.or.ieos==2) THEN
         IF(ieos==1) THEN
           c0 = 0.0d0
         ELSE
           c0 = ( 9.d0*k0*d2k0 + 9.d0*dk0**2-63.d0*dk0+143.d0 )/48.d0
         ENDIF
         c1 = 3.d0*(dk0-4.d0)/8.d0
         DO i=1,npt
            x = vol0/v0(i)
            efit(i) = 9.d0*k0*vol0*( (-0.5d0+c1-c0)*x**(2.d0/3.d0)/2.d0 &
                         +( 0.50-2.d0*c1+3.d0*c0)*x**(4.d0/3.d0)/4.d0 &
                         +(       c1-3.d0*c0)*x**(6.d0/3.d0)/6.d0 &
                         +(            c0)*x**(8.d0/3.d0)/8.d0 &
                         -(-1.d0/8.d0+c1/6.d0-c0/8.d0) )
         ENDDO
      ELSE
         IF(ieos==3) THEN
            ddk = dk0 + k0*d2k0/dk0
         ELSE
            ddk = dk0
         ENDIF
         DO i=1,npt
            efit(i) = - k0*dk0/ddk*vol0/(ddk-1.d0) &
            + v0(i)*k0*dk0/ddk**2*( (vol0/v0(i))**ddk/(ddk-1.d0)+1.d0) &
            - k0*(dk0-ddk)/ddk*( v0(i)*log(vol0/v0(i)) + v0(i)-vol0 )
         ENDDO
      ENDIF
!
!      emin = equilibrium energy obtained by minimizing chi**2
!
      emin = 0.0d0
      DO i = 1,npt
         emin = emin + etot(i)-efit(i)
      ENDDO
      emin = emin/npt
!
      chisq = 0.0d0
      DO i = 1,npt
          efit(i) = efit(i)+emin
          chisq   = chisq + (etot(i)-efit(i))**2
          IF(present(ediff)) ediff(i) = efit(i)-etot(i)
       ENDDO
      chisq = chisq/npt
!
      RETURN
    END SUBROUTINE eqstate
    !
    ! This subroutine is passed to LMDIF to be minimized
    ! LMDIF takes as input the difference between f_fit and f_real
    !       and computes the chi^2 internally.
    !
    SUBROUTINE EOSDIFF(m_, n_, par_, f_, i_)
       IMPLICIT NONE
       INTEGER, INTENT(in)  :: m_, n_
       INTEGER, INTENT(inout)   :: i_
       REAL(DP),INTENT(in)    :: par_(n_)
       REAL(DP),INTENT(out)   :: f_(m_)
       REAL(DP) :: chisq_
       !
         CALL eqstate(n_,par_,chisq_, f_)
      END SUBROUTINE
!
!-----------------------------------------------------------------------
      SUBROUTINE find_minimum(npar,par,chisq)
!-----------------------------------------------------------------------
!
      USE lmdif_module, ONLY : lmdif0
      IMPLICIT NONE
      INTEGER ,INTENT(in)  :: npar
      REAL(DP),INTENT(out) :: par(nmaxpar)
      REAL(DP),INTENT(out) :: chisq
      !
      REAL(DP) :: vchisq(npar)
      REAL(DP) :: ediff(npt)
      INTEGER :: i
      !
      par(1) = v0(npt/2)
      par(2) = 500.0d0
      par(3) = 5.0d0
      par(4) = -0.01d0 ! unused for some eos
      !      
      CALL lmdif0(EOSDIFF, npt, npar, par, ediff, 1.d-12, i)
      !
      IF(i>0 .and. i<5) THEN
!         PRINT*, "Minimization succeeded"
      ELSEIF(i>=5) THEN
         CALL errore("find_minimum", "Minimization stopped before &
                                                           &convergence",1)
      ELSEIF(i<=0) THEN 
        CALL errore("find_minimum", "Minimization error", 1)
      ENDIF
      !
      CALL eqstate(npar,par,chisq)

      END SUBROUTINE find_minimum
!
  END SUBROUTINE ev_sub_nodisk
