!
! Copyright (C) 2013-2016 Andrea Dal Corso
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-------------------------------------------------------------------------
PROGRAM thermo_pw
  !-----------------------------------------------------------------------
  !
  ! ... This is a driver for the calculation of thermodynamic quantities,
  ! ... using the harmonic and/or quasiharmonic approximation and the
  ! ... plane waves pseudopotential method.
  ! ... It reads the input of pw.x and an input that specifies
  ! ... the calculations to do and the parameters for these calculations.
  ! ... It checks the scratch directories to see what has been already
  ! ... calculated. The info for the quantities that have been already
  ! ... calculated is read inside the code. The others tasks are scheduled
  ! ... and distributed to the image driver.
  ! ... If there are several available images the different tasks are
  ! ... carried out in parallel. This driver can carry out a scf 
  ! ... calculation, a non scf calculation to determine the band structure,
  ! ... or a linear response calculation at a given q and for a given
  ! ... representation. Finally the root image can carry out several
  ! ... post processing tasks. The type of calculations currently implemented 
  ! ... are described in the user's guide and in the developer's guide.
  ! ...

  USE kinds,            ONLY : DP

  USE thermo_mod,       ONLY : what, ngeo, energy_geo, tot_ngeo, density,  &
                               start_geometry, last_geometry
  USE control_thermo,   ONLY : lev_syn_1, lev_syn_2, lpwscf_syn_1,         &
                               lbands_syn_1, lph, outdir_thermo, lq2r,     &
                               lconv_ke_test, lconv_nk_test,               &
                               lelastic_const, lecqha, lectqha,            &
                               lpiezoelectric_tensor, lpolarization,       &
                               lpart2_pw, all_geometries_together
  USE control_pwrun,    ONLY : do_punch
  USE control_elastic_constants, ONLY : elastic_algorithm
  USE control_2d_bands, ONLY : only_bands_plot
  USE control_mur,      ONLY : lmurn
  USE control_xrdp,     ONLY : lxrdp
!
!  library helper routines and variables
!
  USE elastic_constants, ONLY : sigma_geo
  USE piezoelectric_tensor, ONLY : polar_geo 
!
!  variables of pw or phonon used here
!
  USE input_parameters, ONLY : outdir
  USE ions_base,        ONLY : tau
  USE cell_base,        ONLY : at, omega, celldm

  USE io_files,         ONLY : tmp_dir, wfc_dir, check_tempdir
  USE check_stop,       ONLY : max_seconds
!
!  parallelization control 
!
  USE check_stop,       ONLY : check_stop_init
  USE mp_global,        ONLY : mp_startup, mp_global_end
  USE environment,      ONLY : environment_start, environment_end
  USE mp_images,        ONLY : nimage, nproc_image, my_image_id, root_image
  USE io_global,        ONLY : stdout, meta_ionode_id
  USE mp_world,         ONLY : world_comm
  USE mp_pools,         ONLY : intra_pool_comm
  USE mp_bands,         ONLY : intra_bgrp_comm, inter_bgrp_comm
  USE mp_diag,          ONLY : mp_start_diag
  USE mp_asyn,          ONLY : with_asyn_images, stop_signal_activated
  USE mp,               ONLY : mp_sum, mp_bcast, mp_barrier
  USE command_line_options,  ONLY : ndiag_
  !
  IMPLICIT NONE
  !
  INTEGER  :: part, nwork, igeom, exit_status, iaux
  LOGICAL  :: exst, parallelfs, run
  CHARACTER (LEN=9)   :: code = 'THERMO_PW'
  CHARACTER (LEN=256) :: auxdyn=' '
  !
  ! Initialize MPI, clocks, print initial messages
  !
  CALL mp_startup ( start_images=.TRUE. )
  CALL mp_start_diag ( ndiag_, world_comm, intra_bgrp_comm, &
       do_distr_diag_inside_bgrp_ = .true. )
  CALL set_mpi_comm_4_solvers( intra_pool_comm, intra_bgrp_comm, &
       inter_bgrp_comm )
  CALL environment_start ( code )
  CALL start_clock( 'PWSCF' )
  with_asyn_images=(nimage > 1)
  !
  ! ... and begin with the initialization part
  !
  CALL thermo_readin()
  !
  CALL thermo_setup()
  !
  CALL thermo_summary()
  !
  CALL check_stop_init(max_seconds)
  !
  part = 1
  !
  CALL initialize_thermo_work(nwork, part, iaux)
  !
  !  In this part the images work asynchronously. No communication is
  !  allowed except though the master-workers mechanism
  !
  CALL run_thermo_asynchronously(nwork, part, iaux, auxdyn)
  !
  !  In this part all images are synchronized and can communicate 
  !  their results thought the world_comm communicator
  !
  IF (nwork>0) THEN
     CALL mp_sum(energy_geo, world_comm)
     energy_geo=energy_geo / nproc_image
  ENDIF
!
!  In the kinetic energy test write the results
!
  IF (lconv_ke_test) THEN
     CALL write_e_ke()
     CALL plot_e_ke()
  ENDIF
!
! In the k-point test write the results
!
  IF (lconv_nk_test) THEN
     CALL write_e_nk()
     CALL plot_e_nk()
  ENDIF
!
!  In a Murnaghan equation calculation determine the lattice constant,
!  bulk modulus and its pressure derivative and write the results.
!  Otherwise interpolate the energy with a quadratic or quartic polynomial.
!
  IF (lev_syn_1) THEN
!
!   minimize the energy and find the equilibrium geometry
!
     CALL manage_energy_minimum(nwork)
!
!  recompute the density at the minimum volume
!
     CALL compute_density(omega,density)
!
!  compute the xrdp at the minimum volume if required by the user
!
     IF (lxrdp) CALL manage_xrdp(' ')

  ENDIF

  IF (lecqha) CALL manage_elastic_cons(nwork, 1)

  CALL deallocate_asyn()

  IF (lpwscf_syn_1) THEN
     with_asyn_images=.FALSE.
     outdir=TRIM(outdir_thermo)//'/g1/'
     tmp_dir = TRIM ( outdir )
     wfc_dir = tmp_dir
     CALL check_tempdir ( tmp_dir, exst, parallelfs )

     IF (my_image_id==root_image) THEN
!
!   do the self consistent calculation at the new lattice constant
!
        do_punch=.TRUE.
        IF (.NOT.only_bands_plot) THEN
           WRITE(stdout,'(/,2x,76("+"))')
           WRITE(stdout,'(5x,"Doing a self-consistent calculation", i5)') 
           WRITE(stdout,'(2x,76("+"),/)')
           CALL check_existence(0,1,0,run)
           IF (run) THEN
              CALL do_pwscf(exit_status, .TRUE.)
              CALL save_existence(0,1,0)
           END IF

           IF (lxrdp) CALL manage_xrdp('.scf')

        ENDIF

        IF (lbands_syn_1) CALL manage_bands()

     ENDIF
     CALL mp_bcast(tau, meta_ionode_id, world_comm)
     CALL mp_bcast(celldm, meta_ionode_id, world_comm)
     CALL mp_bcast(at, meta_ionode_id, world_comm)
     CALL mp_bcast(omega, meta_ionode_id, world_comm)
     CALL set_equilibrium_conf(celldm, tau, at, omega)
     with_asyn_images=(nimage>1)
  END IF
     !
  IF (lpart2_pw) THEN
!
!   here the second part does not use the phonon code. This is for the
!   calculation of elastic constants. We allow the calculation for several
!   geometries
!
     DO igeom=start_geometry,last_geometry

        IF (tot_ngeo > 1) CALL set_geometry_el_cons(igeom)

        part=2
        CALL initialize_thermo_work(nwork, part, iaux)
        !
        !  Asynchronous work starts again. No communication is
        !  allowed except though the master workers mechanism
        !
        CALL run_thermo_asynchronously(nwork, part, igeom, auxdyn)
        !
        ! here we return synchronized and calculate the elastic constants 
        ! from energy or stress 
        !
        IF (lelastic_const) THEN
           IF (elastic_algorithm == 'energy_std'.OR. &
                            elastic_algorithm=='energy') THEN
        !
        !   recover the energy calculated by all images
        !
              CALL mp_sum(energy_geo, world_comm)
              energy_geo=energy_geo / nproc_image
           ELSE
        !
        !   recover the stress tensors calculated by all images
        !
              CALL mp_sum(sigma_geo, world_comm)
              sigma_geo=sigma_geo / nproc_image
           ENDIF

           CALL manage_elastic_cons(nwork, igeom)
        ENDIF

        IF (lpiezoelectric_tensor) THEN
           CALL mp_sum(polar_geo, world_comm)
           polar_geo=polar_geo / nproc_image

           CALL manage_piezo_tensor(nwork)
        END IF

        IF (lpolarization) THEN
           CALL mp_sum(polar_geo, world_comm)
           polar_geo=polar_geo / nproc_image
           CALL print_polarization(polar_geo(:,1), .TRUE. )
        ENDIF

        CALL deallocate_asyn()
     ENDDO
  ENDIF

  IF (what(1:8) /= 'mur_lc_t') ngeo=1
!
!   This part makes one or several phonon calculations, using the
!   image feature of this code and running asynchronously.
!
  IF (lph) THEN

     IF (all_geometries_together) THEN
        CALL manage_all_geometries_ph()
     ELSE
        CALL manage_ph()
     ENDIF
     IF (stop_signal_activated) GOTO 1000
!
!     Here the Helmholtz free energy at each geometry is available.
!     We can write on file the free energy as a function of the volume at
!     any temperature. For each temperature we can fit the free energy
!     or the Gibbs energy if we have a finite pressure with a 
!     Murnaghan equation or with a quadratic or quartic polynomial. 
!     We save the minimum volume or crystal parameters. With the Murnaghan fit
!     we save also the bulk modulus and its pressure derivative for each 
!     temperature.
!
     IF (lev_syn_2) THEN
        CALL mp_barrier(world_comm)
        IF (lmurn) THEN
           CALL manage_anhar()
        ELSE
           CALL manage_anhar_anis()
        ENDIF
     ENDIF

     IF (lecqha) CALL write_elastic_qha()
     IF (lectqha) CALL write_elastic_t_qha()

  ENDIF
  !
1000  CALL deallocate_thermo()
  !
  CALL environment_end( code )
  CALL unset_mpi_comm_4_solvers()
  !
  CALL mp_global_end ()
  !
  STOP
  !
END PROGRAM thermo_pw
