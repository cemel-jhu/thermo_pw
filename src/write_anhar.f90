!
! Copyright (C) 2013-2017 Andrea Dal Corso
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-----------------------------------------------------------------------
SUBROUTINE write_anharmonic()
!-----------------------------------------------------------------------
!
!   This routine writes on output the anharmonic quantities calculated
!   at the volume that minimize the free energy (computed from phonon dos)
!
USE kinds,          ONLY : DP
USE temperature,    ONLY : ntemp, temp
USE thermodynamics, ONLY : ph_e0, ph_ce, ph_b_fact, ph_ener, ph_free_ener, ph_entropy
USE anharmonic,     ONLY : alpha_t, beta_t, gamma_t, cp_t, cv_t, ce_t, ener_t, &
                           free_ener_t, entropy_t, b0_s, vmin_t, free_e_min_t, b0_t, & 
                           b01_t, bfact_t, celldm_t
USE data_files,     ONLY : flanhar
USE control_thermo, ONLY : with_eigen

IMPLICIT NONE
CHARACTER(LEN=256) :: filename

REAL(DP) :: e0

CALL compute_beta(vmin_t, beta_t, temp, ntemp)

alpha_t = beta_t / 3.0_DP

CALL interpolate_thermo(vmin_t, celldm_t, ph_ce, ce_t) 
cv_t=ce_t
CALL compute_cp_bs_g(beta_t, vmin_t, b0_t, cv_t, cp_t, b0_s, gamma_t)
!
!   here we plot the quantities calculated from the phonon dos
!
filename="anhar_files/"//TRIM(flanhar)
CALL add_pressure(filename)

CALL write_ener_beta(temp, vmin_t, free_e_min_t, beta_t, ntemp, filename)
!
!   here the bulk modulus and the gruneisen parameter
!
filename="anhar_files/"//TRIM(flanhar)//'.bulk_mod'
CALL add_pressure(filename)

CALL write_bulk_anharm(temp, b0_t, b0_s, ntemp, filename)
!
!   here the derivative of the bulk modulus with respect to pressure
!
filename="anhar_files/"//TRIM(flanhar)//'.dbulk_mod'
CALL add_pressure(filename)

CALL write_dbulk_anharm(temp, b01_t, ntemp, filename)
!
!   here the heat capacities (constant strain and constant stress)
!
filename="anhar_files/"//TRIM(flanhar)//'.heat'
CALL add_pressure(filename)

CALL write_heat_anharm(temp, cv_t, cv_t, cp_t, ntemp, filename)
!
!  here the average Gruneisen parameter and the quantities that form it
!
filename="anhar_files/"//TRIM(flanhar)//'.gamma'
CALL add_pressure(filename)

CALL write_gamma_anharm(temp, gamma_t, cv_t, beta_t, b0_t, ntemp, filename)

!
!   here the vibrational energy, entropy, zero point energy 
!

CALL interpolate_thermo(vmin_t, celldm_t, ph_ener, ener_t)

CALL interpolate_thermo(vmin_t, celldm_t, ph_free_ener, free_ener_t)

CALL interpolate_thermo(vmin_t, celldm_t, ph_entropy, entropy_t)

CALL interpolate_e0(vmin_t, celldm_t, ph_e0, e0) 

filename="anhar_files/"//TRIM(flanhar)//'.therm'
CALL add_pressure(filename)
CALL write_thermo_anharm(temp, ntemp, e0, ener_t, free_ener_t, &
                                                 entropy_t, cv_t, filename)
!
!   here the b factors
!
IF (with_eigen) THEN
   CALL interpolate_b_fact(vmin_t, ph_b_fact, bfact_t)
   filename="anhar_files/"//TRIM(flanhar)
   CALL add_pressure(filename)
   CALL write_anharm_bfact(temp, bfact_t, ntemp, filename)
END IF


RETURN
END SUBROUTINE write_anharmonic

!-----------------------------------------------------------------------
SUBROUTINE write_ph_freq_anharmonic()
!-----------------------------------------------------------------------
USE kinds,          ONLY : DP
USE temperature,    ONLY : ntemp, temp
USE control_thermo, ONLY : with_eigen
USE ph_freq_thermodynamics, ONLY : phf_e0, phf_ce, phf_b_fact, phf_ener, &
                                   phf_free_ener, phf_entropy
USE ph_freq_anharmonic, ONLY : alphaf_t, betaf_t, gammaf_t, cpf_t, cvf_t, &
                        cef_t, enerf_t, free_enerf_t, entropyf_t, b0f_s, free_e_minf_t, & 
                        vminf_t, b0f_t, b01f_t, bfactf_t, celldmf_t
USE data_files,     ONLY : flanhar

IMPLICIT NONE
CHARACTER(LEN=256) :: filename

REAL(DP) :: e0

CALL compute_beta(vminf_t, betaf_t, temp, ntemp)

alphaf_t = betaf_t / 3.0_DP

CALL interpolate_thermo(vminf_t, celldmf_t, phf_ce, cef_t) 
cvf_t=cef_t
CALL compute_cp_bs_g(betaf_t, vminf_t, b0f_t, cvf_t, cpf_t, b0f_s, gammaf_t)
!
!   here we plot the quantities calculated from the phonon dos
!
filename="anhar_files/"//TRIM(flanhar)//'_ph'
CALL add_pressure(filename)

CALL write_ener_beta(temp, vminf_t, free_e_minf_t, betaf_t, ntemp, filename)
!
!   here the bulk modulus and the gruneisen parameter
!
filename="anhar_files/"//TRIM(flanhar)//'.bulk_mod_ph'
CALL add_pressure(filename)

CALL write_bulk_anharm(temp, b0f_t, b0f_s, ntemp, filename)
!
!   here the derivative of the bulk modulus with respect to pressure
!
filename="anhar_files/"//TRIM(flanhar)//'.dbulk_mod_ph'
CALL add_pressure(filename)

CALL write_dbulk_anharm(temp, b01f_t, ntemp, filename)
!
!   here the heat capacities (constant strain and constant stress)
!
filename="anhar_files/"//TRIM(flanhar)//'.heat_ph'
CALL add_pressure(filename)

CALL write_heat_anharm(temp, cvf_t, cvf_t, cpf_t, ntemp, filename)
!
!  here the average Gruneisen parameter and the quantities that form it
!
filename="anhar_files/"//TRIM(flanhar)//'.gamma_ph'
CALL add_pressure(filename)

CALL write_gamma_anharm(temp, gammaf_t, cvf_t, betaf_t, b0f_t, ntemp, filename)

!
!   here the vibrational energy, entropy, zero point energy 
!

CALL interpolate_thermo(vminf_t, celldmf_t, phf_ener, enerf_t) 

CALL interpolate_thermo(vminf_t, celldmf_t, phf_free_ener, free_enerf_t)

CALL interpolate_thermo(vminf_t, celldmf_t, phf_entropy, entropyf_t)

CALL interpolate_e0(vminf_t, celldmf_t, phf_e0, e0)

filename="anhar_files/"//TRIM(flanhar)//'.therm_ph'
CALL add_pressure(filename)
CALL write_thermo_anharm(temp, ntemp, e0, enerf_t, free_enerf_t, & 
                                            entropyf_t, cvf_t, filename)
!
!   here the b factors
!
IF (with_eigen) THEN
   CALL interpolate_b_fact(vminf_t, phf_b_fact, bfactf_t)
   filename="anhar_files/"//TRIM(flanhar)//'_ph'
   CALL add_pressure(filename)
   CALL write_anharm_bfact(temp, bfactf_t, ntemp, filename)
END IF

RETURN
END SUBROUTINE write_ph_freq_anharmonic

!-----------------------------------------------------------------------
SUBROUTINE write_grun_anharmonic()
!-----------------------------------------------------------------------
!
!  This routine computes the anharmonic properties from the Gruneisen
!  parameters. Used when lmurn=.TRUE.. (Assumes to have the volume and
!  the bulk modulus as a function of temperature).
!  
!
USE kinds,          ONLY : DP
USE constants,      ONLY : ry_kbar
USE ions_base,      ONLY : nat
USE temperature,    ONLY : ntemp, temp
USE thermo_mod,     ONLY : ngeo, no_ph
USE ph_freq_thermodynamics, ONLY : ph_freq_save
USE grun_anharmonic, ONLY : betab, cp_grun_t, b0_grun_s, &
                           grun_gamma_t, poly_grun, poly_degree_grun, &
                           ce_grun_t, cv_grun_t
USE ph_freq_module, ONLY : thermal_expansion_ph, ph_freq_type,  &
                           destroy_ph_freq, init_ph_freq
USE polyfit_mod,    ONLY : compute_poly, compute_poly_deriv
USE isoentropic,    ONLY : isobaric_heat_capacity
USE control_grun,   ONLY : vgrun_t, b0_grun_t
USE control_dosq,   ONLY : nq1_d, nq2_d, nq3_d
USE data_files,     ONLY : flanhar
USE io_global,      ONLY : meta_ionode
USE mp_world,       ONLY : world_comm
USE mp,             ONLY : mp_sum

IMPLICIT NONE
CHARACTER(LEN=256) :: filename
INTEGER :: itemp, iu_therm, i, nq, imode, iq, startq, lastq, iq_eff
TYPE(ph_freq_type) :: ph_freq    ! the frequencies at the volumes at
                                 ! which the gruneisen parameters are 
                                 ! calculated
TYPE(ph_freq_type) :: ph_grun    ! the gruneisen parameters recomputed
                                 ! at each temperature at the volume
                                 ! corresponding to that temperature
REAL(DP) :: vm, f, g
INTEGER :: find_free_unit, central_geo
!
!  divide the q vectors among the processors. Allocate space to save the
!  frequencies and the gruneisen parameter on a part of the mesh of q points.
!
CALL find_central_geo(ngeo,no_ph,central_geo)
nq=ph_freq_save(central_geo)%nq
startq=ph_freq_save(central_geo)%startq
lastq=ph_freq_save(central_geo)%lastq

CALL init_ph_freq(ph_grun, nat, nq1_d, nq2_d, nq3_d, startq, &
                                                         lastq, nq, .FALSE.)
CALL init_ph_freq(ph_freq, nat, nq1_d, nq2_d, nq3_d, startq, &
                                                         lastq, nq, .FALSE.)
ph_freq%wg(:)=ph_freq_save(central_geo)%wg(:)

betab=0.0_DP
DO itemp = 1, ntemp
!
!  Set the volume at this temperature.
!
   vm=vgrun_t(itemp)
!
!  Use the fitting polynomials to find the frequencies and the gruneisen
!  parameters at this volume.
!
   ph_freq%nu= 0.0_DP
   ph_grun%nu= 0.0_DP
   iq_eff=0
   DO iq=startq, lastq
      iq_eff=iq_eff+1
      DO imode=1,3*nat
         CALL compute_poly(vm, poly_degree_grun, poly_grun(:,imode,iq),f)
         CALL compute_poly_deriv(vm, poly_degree_grun, poly_grun(:,imode,iq),g)
!
!     g here is d w / d V 
!     ph_grun%nu will contain the gruneisen parameter divided by the volume
!     as requested by the thermal_expansion_ph routine
!
         ph_freq%nu(imode,iq_eff)=f
         IF ( f > 0.0_DP) THEN 
            ph_grun%nu(imode,iq_eff)=-g/f
         ELSE
            ph_grun%nu(imode,iq_eff) = 0.0_DP
         ENDIF
      ENDDO
   ENDDO
!
!  computes thermal expansion from gruneisen parameters. 
!  this routine gives betab multiplied by the bulk modulus
!
   CALL thermal_expansion_ph(ph_freq, ph_grun, temp(itemp), betab(itemp), &
                                                            ce_grun_t(itemp))
!
!  divide by the bulk modulus
!
   betab(itemp)=betab(itemp) * ry_kbar / b0_grun_t(itemp)

END DO
CALL mp_sum(betab, world_comm)
CALL mp_sum(ce_grun_t, world_comm)
cv_grun_t=ce_grun_t
!
!  computes the other anharmonic quantities
!
CALL compute_cp_bs_g(betab, vgrun_t, b0_grun_t, cv_grun_t, cp_grun_t, &
                                                 b0_grun_s, grun_gamma_t)
IF (meta_ionode) THEN
!
!   here quantities calculated from the mode Gruneisen parameters
!
   filename="anhar_files/"//TRIM(flanhar)//'.aux_grun'
   CALL add_pressure(filename)
   CALL write_aux_grun(temp, betab, cp_grun_t, ce_grun_t, b0_grun_s, &
                                               b0_grun_t, ntemp, filename) 
!
!  Here the average Gruneisen parameter and the quantities that form it
!
   filename="anhar_files/"//TRIM(flanhar)//'.gamma_grun'
   CALL add_pressure(filename)
   CALL write_gamma_anharm(temp, grun_gamma_t, ce_grun_t, betab, &
                                               b0_grun_t, ntemp, filename)
ENDIF

CALL destroy_ph_freq(ph_freq)
CALL destroy_ph_freq(ph_grun)

RETURN
END SUBROUTINE write_grun_anharmonic

!-----------------------------------------------------------------------
SUBROUTINE compute_beta(vmin_t, beta_t, temp, ntemp)
!-----------------------------------------------------------------------
!
!  This routine receives as input the volume for ntemp temperatures
!  and computes the volume thermal expansion for ntemp-2 temperatures.
!  In the first and last point the thermal expansion is not computed.
!
USE kinds, ONLY : DP
USE mp,    ONLY : mp_sum
USE mp_world, ONLY : world_comm

IMPLICIT NONE
INTEGER, INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: vmin_t(ntemp), temp(ntemp)
REAL(DP), INTENT(OUT) :: beta_t(ntemp) 

INTEGER :: itemp, startt, lastt

beta_t=0.0_DP
CALL divide(world_comm, ntemp, startt, lastt)
!
!  just interpolate linearly
!
DO itemp = max(2,startt), min(ntemp-1, lastt)
   beta_t(itemp) = (vmin_t(itemp+1)-vmin_t(itemp-1)) / &
                   (temp(itemp+1)-temp(itemp-1)) / vmin_t(itemp)
END DO
CALL mp_sum(beta_t, world_comm)

RETURN
END SUBROUTINE compute_beta

!-----------------------------------------------------------------------
SUBROUTINE write_ener_beta(temp, vmin, emin, beta, ntemp, filename)
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER, INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), emin(ntemp), vmin(ntemp), beta(ntemp)
CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')

   WRITE(iu_therm,'("# beta is the volume thermal expansion ")')
   WRITE(iu_therm,'("#   T (K)         V(T) (a.u.)^3          F (T) (Ry) &
                   &      beta (10^(-6) K^(-1))")' )

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(e12.5,2e23.13,e18.8)') temp(itemp), &
                vmin(itemp), emin(itemp), beta(itemp)*1.D6
   END DO
  
   CLOSE(iu_therm)
ENDIF
RETURN
END SUBROUTINE write_ener_beta

!-----------------------------------------------------------------------
SUBROUTINE write_bulk_anharm(temp, b0t, b0s, ntemp, filename)
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER, INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), b0t(ntemp), b0s(ntemp)
CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')

   WRITE(iu_therm,'("#  ")')
   WRITE(iu_therm,'("#   T (K)        B_T(T) (kbar)        B_S(T) (kbar) &
                                 &       B_S(T)-B_T(T) (kbar) ")')

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(e12.5,3e22.13)') temp(itemp), &
                 b0t(itemp), b0s(itemp), b0s(itemp)-b0t(itemp)
   END DO
  
   CLOSE(iu_therm)
ENDIF
RETURN
END SUBROUTINE write_bulk_anharm

!-----------------------------------------------------------------------
SUBROUTINE write_dbulk_anharm(temp, b01t, ntemp, filename)
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER, INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), b01t(ntemp)
CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')

   WRITE(iu_therm,'("#  ")')
   WRITE(iu_therm,'("#   T (K)          dB/dp (T) ")')

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(e12.5,e23.13)') temp(itemp), b01t(itemp)
   END DO
  
   CLOSE(iu_therm)
ENDIF
RETURN
END SUBROUTINE write_dbulk_anharm

!-----------------------------------------------------------------------
SUBROUTINE write_gamma_anharm(temp, gammat, cvt, beta, b0t, ntemp, filename)
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER,  INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), gammat(ntemp), cvt(ntemp), beta(ntemp), &
                                     b0t(ntemp)
CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')

   WRITE(iu_therm,'("# ")')
   WRITE(iu_therm,'("# T (K)          gamma(T)             C_V(T) &
                              &(Ry/cell/K)    beta B_T (kbar/K)")')

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(e12.5,3e22.13)') temp(itemp), gammat(itemp), &
                                         cvt(itemp), beta(itemp)*b0t(itemp)
   ENDDO
   CLOSE(iu_therm)
ENDIF

RETURN
END SUBROUTINE write_gamma_anharm

!-----------------------------------------------------------------------
SUBROUTINE write_heat_anharm(temp, cet, cvt, cpt, ntemp, filename)
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER,  INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), cet(ntemp), cvt(ntemp), cpt(ntemp)
CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')

   WRITE(iu_therm,'("# ")')
   WRITE(iu_therm,'("# T (K)        C_e(T) (Ry/cell/K)    (C_P-C_V)(T) &
                              &(Ry/cell/K)     C_e+C_P-C_V(T) (Ry/cell/K)")')

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(e12.5,3e22.13)') temp(itemp), &
                 cet(itemp), cpt(itemp)-cvt(itemp), cet(itemp)+cpt(itemp)&
                                                              -cvt(itemp)
   ENDDO
   CLOSE(iu_therm)
ENDIF

RETURN
END SUBROUTINE write_heat_anharm

!-----------------------------------------------------------------------
SUBROUTINE write_aux_grun(temp, betab, cp_grun_t, cv_grun_t, b0_grun_s, b0_t, &
                                                           ntemp, filename) 
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER, INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), betab(ntemp), cp_grun_t(ntemp), &
                        cv_grun_t(ntemp), b0_grun_s(ntemp), b0_t(ntemp)

CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')
   WRITE(iu_therm,'("# gamma is the average gruneisen parameter ")')
   WRITE(iu_therm,'("#   T (K)         beta(T)x10^6 &
            &   (C_p - C_v)(T)   (B_S - B_T) (T) (kbar) " )' )

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(4e16.8)') temp(itemp), betab(itemp)*1.D6,    &
                        cp_grun_t(itemp)-cv_grun_t(itemp),   &
                        b0_grun_s(itemp) - b0_t(itemp)
   ENDDO
   CLOSE(iu_therm)
END IF

RETURN
END SUBROUTINE write_aux_grun

!-----------------------------------------------------------------------
SUBROUTINE set_volume_b0_grun()
!-----------------------------------------------------------------------

USE control_grun,       ONLY : lv0_t, lb0_t, vgrun_t, celldm_grun_t, &
                               b0_grun_t
USE control_thermo,     ONLY : ltherm_dos, ltherm_freq
USE temperature,        ONLY : ntemp
USE anharmonic,         ONLY : vmin_t, celldm_t, b0_t
USE ph_freq_anharmonic, ONLY : vminf_t, celldmf_t, b0f_t
USE equilibrium_conf,   ONLY : celldm0, omega0
USE control_mur,        ONLY : b0

IMPLICIT NONE

INTEGER :: itemp

DO itemp=1, ntemp
   IF (lv0_t.AND.ltherm_freq) THEN
      vgrun_t(itemp)=vminf_t(itemp)
      celldm_grun_t(:,itemp)=celldmf_t(:,itemp)
   ELSEIF (lv0_t.AND.ltherm_dos) THEN
      vgrun_t(itemp)=vmin_t(itemp)
      celldm_grun_t(:,itemp)=celldm_t(:,itemp)
   ELSE
      vgrun_t(itemp)=omega0
      celldm_grun_t(:,itemp)=celldm0(:)
   ENDIF

   IF (lb0_t.AND.ltherm_freq) THEN
      b0_grun_t(itemp)=b0f_t(itemp)
   ELSEIF(lb0_t.AND.ltherm_dos) THEN
      b0_grun_t(itemp)=b0_t(itemp)
   ELSE
      b0_grun_t(itemp)=b0
   ENDIF
ENDDO

RETURN
END SUBROUTINE set_volume_b0_grun
!
! Copyright (C) 2018 Cristiano Malica
!
!-----------------------------------------------------------------------
SUBROUTINE write_anharm_bfact(temp, bfact_t, ntemp, filename)
!-----------------------------------------------------------------------

USE ions_base, ONLY : nat
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER,  INTENT(IN) :: ntemp 
REAL(DP), INTENT(IN) :: temp(ntemp), bfact_t(6,nat,ntemp)
CHARACTER(LEN=256) :: filename

INTEGER :: na, ijpol
INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

CHARACTER(LEN=6) :: int_to_char

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   DO na=1, nat
      OPEN(UNIT=iu_therm, FILE=TRIM(filename)//'.'//&
           TRIM(int_to_char(na))//'.dw', STATUS='UNKNOWN', FORM='FORMATTED')
      WRITE(iu_therm,'("# A^2")')

      WRITE(iu_therm,'("#",5x,"T (K)",10x,"B_11",14x,"B_12",14x,"B_13",14x,"B_22",&
                           &14x,"B_23",14x,"B_33")')

      DO itemp = 1, ntemp
      WRITE(iu_therm, '(e16.8,6e18.8)') temp(itemp), (bfact_t(ijpol,na,itemp),&
                                        ijpol=1,6)
      ENDDO
      CLOSE(UNIT=iu_therm, STATUS='KEEP')
   ENDDO
ENDIF
RETURN
END SUBROUTINE write_anharm_bfact

!-----------------------------------------------------------------------
SUBROUTINE write_thermo_anharm(temp, ntemp, e0, ener_t, free_e_min_t, &
                                                entropy_t, cv_t, filename)
!-----------------------------------------------------------------------
USE kinds,     ONLY : DP
USE io_global, ONLY : meta_ionode
IMPLICIT NONE
INTEGER, INTENT(IN) :: ntemp
REAL(DP), INTENT(IN) :: temp(ntemp), ener_t(ntemp), free_e_min_t(ntemp), &
                        cv_t(ntemp), entropy_t(ntemp), e0
CHARACTER(LEN=*) :: filename

INTEGER :: itemp, iu_therm
INTEGER :: find_free_unit

IF (meta_ionode) THEN
   iu_therm=find_free_unit()
   OPEN(UNIT=iu_therm, FILE=TRIM(filename), STATUS='UNKNOWN', FORM='FORMATTED')
   WRITE(iu_therm,'("# Zero point energy:", f8.5, " Ry/cell,", f9.5, &
                 &" kJ/(N mol),", f9.5, " kcal/(N mol)")') e0, &
                    e0 * 1313.313_DP, e0 * 313.7545_DP
   WRITE(iu_therm,'("# Temperature T in K, ")')
   WRITE(iu_therm,'("# Energy and free energy in Ry/cell,")')
   WRITE(iu_therm,'("# Entropy in Ry/cell/K,")')
   WRITE(iu_therm,'("# Heat capacity Cv in Ry/cell/K.")')
   WRITE(iu_therm,'("# Multiply by 13.6058 to have energies in &
                          &eV/cell etc..")')
   WRITE(iu_therm,'("# Multiply by 13.6058 x 23060.35 = 313 754.5 to have &
                     &energies in cal/(N mol).")')
   WRITE(iu_therm,'("# Multiply by 13.6058 x 96526.0 = 1 313 313 to &
                     &have energies in J/(N mol).")')
   WRITE(iu_therm,'("# N is the number of formula units per cell.")')
   WRITE(iu_therm,'("# For instance in silicon N=2. Divide by N to have &
                &energies in cal/mol etc. ")')
   WRITE(iu_therm,'("#",5x,"   T  ", 10x, " energy ", 10x, "  free energy ",&
               & 12x, " entropy ", 17x, " Cv ")')

   DO itemp = 2, ntemp-1
      WRITE(iu_therm, '(e12.5,e23.13,e23.13,e23.13,e23.13)') temp(itemp),    &
                       ener_t(itemp), free_e_min_t(itemp), entropy_t(itemp), &
                       cv_t(itemp)
   END DO

   CLOSE(iu_therm)
ENDIF
RETURN
END SUBROUTINE write_thermo_anharm
