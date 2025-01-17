!
! Copyright (C) 2022 Andrea Dal Corso
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!---------------------------------------------------------------------
SUBROUTINE manage_plot_anhar()
!---------------------------------------------------------------------
!
!  This routine call all the routines that plot quasi-anharmonic quantities
!  in the p-V thermodynamics
!
USE control_mur, ONLY : lmurn
IMPLICIT NONE

CALL plot_anhar_energy()
CALL plot_anhar_volume() 
CALL plot_anhar_press()
CALL plot_anhar_bulk() 
CALL plot_anhar_dbulk()
CALL plot_anhar_beta()
CALL plot_anhar_heat()
CALL plot_anhar_gamma()
CALL plot_anhar_thermo()
IF (lmurn) THEN
   CALL plot_anhar_dw()
!
   CALL plot_hugoniot()
!
   CALL plot_t_debye()
ENDIF
RETURN
END SUBROUTINE manage_plot_anhar
!
!---------------------------------------------------------------------
SUBROUTINE manage_plot_anhar_anis()
!---------------------------------------------------------------------
!
!  This routine calls all the routines that plot quasi-anharmonic quantities
!  in the stress-strain thermodynamics and then call the previous routine
!  to plot the p-V thermodynamic quantities
!
IMPLICIT NONE

CALL plot_anhar_anis_celldm()
CALL plot_anhar_anis_alpha()
CALL plot_anhar_anis_dw()
CALL plot_thermal_stress()
CALL plot_generalized_gruneisen()
!
!  and here the p-V thermodynamic quantities
!
CALL manage_plot_anhar()

RETURN
END SUBROUTINE manage_plot_anhar_anis

