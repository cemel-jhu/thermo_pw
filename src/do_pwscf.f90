!
! Copyright (C) 2013-2017 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
SUBROUTINE do_pwscf ( exit_status, lscf_ ) 
  !----------------------------------------------------------------------------
  !
  !! author: Paolo Giannozzi
  !! license: GNU 
  !! summary: Run an instance of the Plane Wave Self-Consistent Field code
  !!
  !! Run an instance of the Plane Wave Self-Consistent Field code 
  !! MPI initialization and input data reading is performed in the 
  !! calling code - returns in exit_status the exit code for pw.x, 
  !! returned in the shell. Values are:
  !! * 0: completed successfully
  !! * 1: an error has occurred (value returned by the errore() routine)
  !! * 2-127: convergence error
  !!   * 2: scf convergence error
  !!   * 3: ion convergence error
  !! * 128-255: code exited due to specific trigger
  !!   * 255: exit due to user request, or signal trapped,
  !!          or time > max_seconds
  !!     (note: in the future, check_stop_now could also return a value
  !!     to specify the reason of exiting, and the value could be used
  !!     to return a different value for different reasons)
  !! @Note
  !! 10/01/17 Samuel Ponce: Add Ford documentation
  !! @endnote
  !!
  !
  USE io_global,        ONLY : stdout, ionode, ionode_id
  USE parameters,       ONLY : ntypx, npk, lmaxx
  USE initial_param,    ONLY : ethr0
  USE cell_base,        ONLY : fix_volume, fix_area
  USE control_flags,    ONLY : conv_elec, gamma_only, ethr, lscf
  USE control_flags,    ONLY : conv_ions, istep, nstep, restart, lmd, lbfgs
  USE command_line_options, ONLY : command_line
  USE force_mod,        ONLY : lforce, lstres, sigma, force
  USE check_stop,       ONLY : check_stop_init, check_stop_now
  USE basis,            ONLY : starting_pot, startingconfig
  USE mp_images,        ONLY : intra_image_comm
  USE extrapolation,    ONLY : update_file, update_pot
  USE scf,              ONLY : rho
  USE lsda_mod,         ONLY : nspin
  USE fft_base,         ONLY : dfftp
  USE qmmm,             ONLY : qmmm_initialization, qmmm_shutdown, &
                               qmmm_update_positions, qmmm_update_forces
  USE qexsd_module,     ONLY : qexsd_set_status
  USE funct,            ONLY : dft_is_hybrid, stop_exx
  !
  IMPLICIT NONE
  INTEGER, INTENT(OUT) :: exit_status
  !! Gives the exit status at the end
  LOGICAL :: lscf_
  LOGICAL, external :: matches
  !! checks if first string is contained in the second
  INTEGER :: idone 
  !! counter of electronic + ionic steps done in this run
  INTEGER :: ions_status 
  !!    ions_status =  3  not yet converged
  !!    ions_status =  2  converged, restart with nonzero magnetization
  !!    ions_status =  1  converged, final step with current cell needed
  !!    ions_status =  0  converged, exiting
  !
  exit_status = 0
  ions_status = 3
  IF ( ionode ) WRITE( unit = stdout, FMT = 9010 ) ntypx, npk, lmaxx
  !
  IF ( gamma_only ) WRITE( UNIT = stdout, &
     & FMT = '(/,5X,"gamma-point specific algorithms are used")' )

  IF (lscf_) THEN
     starting_pot ='atomic'
     startingconfig='input'
     lscf=.TRUE.
  ELSE
     starting_pot ='file'
     startingconfig='file'
     lscf=.FALSE.
     lbfgs=.FALSE.
     lforce=.FALSE.
     lstres=.FALSE.
  ENDIF
  ethr=ethr0
  istep=0

  !
  ! call to void routine for user defined / plugin patches initializations
  !
  CALL plugin_initialization()
  !
  CALL setup_tpw ()
  !
  CALL qmmm_update_positions()
  !
  ! ... dry run: code will stop here if called with exit file present
  ! ... useful for a quick and automated way to check input data
  !
  IF ( check_stop_now() ) THEN
     CALL pre_init()
     CALL data_structure( gamma_only )
     CALL summary()
     CALL memory_report()
     CALL qexsd_set_status(255)
     CALL punch( 'init-config' )
     exit_status = 255
     RETURN
  ENDIF
  !
  CALL init_run()
  !
  IF ( check_stop_now() ) THEN
     CALL qexsd_set_status(255)
     CALL punch( 'config' )
     exit_status = 255
     RETURN
  ENDIF
  !
  main_loop: DO idone = 1, nstep
     !
     ! ... electronic self-consistency or band structure calculation
     !
     IF ( .NOT. lscf) THEN
        CALL non_scf ()
     ELSE
        CALL electrons_tpw()
     END IF
     !
     ! ... code stopped by user or not converged
     !
     IF ( check_stop_now() .OR. .NOT. conv_elec ) THEN
        IF ( check_stop_now() ) exit_status = 255
        IF ( .NOT. conv_elec )  exit_status =  2
        CALL qexsd_set_status(exit_status)
        ! workaround for the case of a single k-point
        CALL punch( 'config' )
        RETURN
     ENDIF
     !
     ! ... ionic section starts here
     !
     CALL start_clock( 'ions' ); !write(*,*)' start ions' ; FLUSH(6)
     conv_ions = .TRUE.
     !
     ! ... recover from a previous run, if appropriate
     !
     !IF ( restart .AND. lscf ) CALL restart_in_ions()
     !
     ! ... file in CASINO format written here if required
     !
     IF ( lmd ) THEN
        CALL pw2casino( istep )
     ELSE
        CALL pw2casino( 0 )
     END IF
     !
     ! ... force calculation
     !
     IF ( lforce ) CALL forces()
     !
     ! ... stress calculation
     !
     IF ( lstres ) CALL stress_tpw ( sigma )
     !
     ! ... send out forces to MM code in QM/MM run
     !
     IF ( lmd .OR. lbfgs ) THEN
        !
        if (fix_volume) CALL impose_deviatoric_stress(sigma)
        if (fix_area)  CALL  impose_deviatoric_stress_2d(sigma)
        !
        ! ... save data needed for potential and wavefunction extrapolation
        !
        CALL update_file ( )
        !
        ! ... ionic step (for molecular dynamics or optimization)
        !
        CALL move_ions ( idone, ions_status )
        conv_ions = ( ions_status == 0 )
        !
        ! ... then we save restart information for the new configuration
        !
        IF ( idone <= nstep .AND. .NOT. conv_ions ) THEN 
            CALL qexsd_set_status(255)
            CALL punch( 'config' )
        END IF
        !
        IF (dft_is_hybrid() )  CALL stop_exx()
     END IF
     !
     CALL stop_clock( 'ions' ); !write(*,*)' stop ions' ; FLUSH(6)
     !
     ! ... send out forces to MM code in QM/MM run
     !
     CALL qmmm_update_forces( force, rho%of_r, nspin, dfftp)
     !
     ! ... exit condition (ionic convergence) is checked here
     !
     IF ( lmd .OR. lbfgs ) CALL add_qexsd_step(idone)
     IF ( conv_ions ) EXIT main_loop
     !
     ! ... receive new positions from MM code in QM/MM run
     !
     CALL qmmm_update_positions()
     !
     ! ... terms of the hamiltonian depending upon nuclear positions
     ! ... are reinitialized here
     !
     IF ( lmd .OR. lbfgs ) THEN
        !
        IF ( ions_status == 1 ) THEN
           !
           ! ... final scf calculation with G-vectors for final cell
           !
           CALL reset_gvectors ( )
           !
        ELSE IF ( ions_status == 2 ) THEN
           !
           ! ... check whether nonzero magnetization is real
           !
           CALL reset_magn ( )
           !
        ELSE
           !
           ! ... update the wavefunctions, charge density, potential
           ! ... update_pot initializes structure factor array as well
           !
           CALL update_pot()
           !
           ! ... re-initialize atomic position-dependent quantities
           !
           CALL hinit1()
           !
        END IF
        !
        !
     END IF
     ! ... Reset convergence threshold of iterative diagonalization for
     ! ... the first scf iteration of each ionic step (after the first)
     !
     ethr = 1.0D-6
     !
  END DO main_loop
  !
  ! ... save final data file
  !
  CALL qexsd_set_status(exit_status)
  CALL punch('all')
  !
  IF ( .NOT. conv_ions )  exit_status =  3
  !
  CALL qmmm_shutdown()
  !
  CALL close_files(.TRUE.)
  !
  CALL clean_pw( .FALSE. )

  RETURN
  !
9010 FORMAT( /,5X,'Current dimensions of program PWSCF are:', &
           & /,5X,'Max number of different atomic species (ntypx) = ',I2,&
           & /,5X,'Max number of k-points (npk) = ',I6,&
           & /,5X,'Max angular momentum in pseudopotentials (lmaxx) = ',i2)
  !
END SUBROUTINE do_pwscf

