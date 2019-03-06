!
! Copyright (C) 2001-2017 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-----------------------------------------------------------------------
subroutine zstar_eu_tpw(drhoscf)
  !-----------------------------------------------------------------------
  ! calculate the effective charges Z(E,Us) (E=scf,Us=bare)
  ! This expression is obtained as the derivative of the forces with
  ! respect to the electric field.
  !
  ! epsil =.true. is needed for this calculation to be meaningful
  !
  !
  USE kinds,     ONLY : DP
  USE cell_base, ONLY : bg
  USE ions_base, ONLY : nat, zv, ityp, atm
  USE klist,     ONLY : wk, xk, ngk, igk_k
  USE symme,     ONLY : symtensor
  USE buffers,   ONLY : get_buffer
  USE wvfct,     ONLY : npw, npwx
  USE uspp,      ONLY : vkb
  USE fft_base,  ONLY : dffts
  use noncollin_module, ONLY : nspin_mag, noncolin
  USE wavefunctions,  ONLY: evc

  USE modes,     ONLY : u, nirr, npert
  USE qpoint,    ONLY : npwq, nksq
  USE eqv,       ONLY : dvpsi, dpsi
  USE efield_mod,   ONLY : zstareu0, zstareu
  USE zstar_add, ONLY : zstareu0_rec
  USE units_ph,  ONLY : iudwf, lrdwf
  USE units_lr,  ONLY : lrwfc, iuwfc
  USE control_ph,ONLY : done_zeu
  USE control_lr,ONLY : nbnd_occ
  USE ph_restart, ONLY : ph_writefile
  USE io_global, ONLY : stdout

  USE mp_pools,  ONLY : inter_pool_comm
  USE mp_bands,  ONLY : intra_bgrp_comm
  USE mp,        ONLY : mp_sum
  USE ldaU,      ONLY : lda_plus_u


  implicit none

  complex(DP) :: drhoscf (dffts%nnr, nspin_mag, 3)
  ! output: the change of the scf charge (smooth part only)

  integer :: ipol, jpol, icart, na, nu, mu, imode0, irr, &
       ipert, nrec, mode, ik, ibnd, ierr
  ! counters
  real(DP) :: weight
  !  auxiliary space
  complex(DP), allocatable :: zstareu0_wrk(:,:)
  !
  complex(DP), external :: zdotc
  !  scalar product
  !
  call start_clock ('zstar_eu')

  ALLOCATE( zstareu0_wrk( 3, 3 * nat ) )
  zstareu0_wrk(:,:)=(0.0_DP, 0.0_DP)

  do ik = 1, nksq
     npw=ngk(ik)
     npwq = npw
     weight = wk (ik)
     if (nksq > 1) call get_buffer(evc, lrwfc, iuwfc, ik)
     call init_us_2 (npw, igk_k(1,ik), xk (1, ik), vkb)
     imode0 = 0
     do irr = 1, nirr
        do ipert = 1, npert (irr)
           mode = ipert+imode0
           dvpsi(:,:) = (0.d0, 0.d0)
           !
           ! recalculate  DeltaV*psi(ion) for mode nu
           !
           call dvqpsi_us_only (ik, u (1, mode))
           !
           ! DFPT+U: add the bare variation of the Hubbard potential 
           !
           IF (lda_plus_u) CALL dvqhub_barepsi_us (ik, u(:,mode))
           !
           do jpol = 1, 3
              nrec = (jpol - 1) * nksq + ik
              !
              ! read dpsi(scf)/dE for electric field in jpol direction
              !
              call get_buffer(dpsi, lrdwf, iudwf, nrec)
              DO ibnd=1,nbnd_occ(ik)
                 zstareu0_wrk(jpol,mode)=zstareu0_wrk(jpol,mode)-weight*&
                     ( zdotc(npw,dpsi(1,ibnd),1,dvpsi(1,ibnd),1) + &
                      zdotc(npw,dvpsi(1,ibnd),1,dpsi(1,ibnd),1) )
                 IF (noncolin) &
                    zstareu0_wrk(jpol,mode)=zstareu0_wrk(jpol, mode)- &
                      weight*(zdotc(npw,dpsi(npwx+1,ibnd),1, &
                              dvpsi(npwx+1,ibnd),1) +    &
                    zdotc(npw,dvpsi(npwx+1,ibnd),1,dpsi(npwx+1,ibnd),1) )
              END DO
           enddo
        enddo
        imode0 = imode0 + npert (irr)
     enddo
  enddo
  call zstar_eu_loc (drhoscf, zstareu0_wrk)

  call mp_sum ( zstareu0_wrk, intra_bgrp_comm )
  call mp_sum ( zstareu0_wrk, inter_pool_comm )

!  write(6,*) ' term Z^{(1} wrk'
!  CALL tra_write_zstar(zstareu0_wrk, zstareu, .TRUE.)
!  write(6,*) ' term Z^{(1} 0'
!  CALL tra_write_zstar(zstareu0, zstareu, .TRUE.)
!  write(6,*) ' term Z^{(1} rec'
!  CALL tra_write_zstar(zstareu0_rec, zstareu, .TRUE.)

  zstareu0_wrk = zstareu0 + zstareu0_wrk + zstareu0_rec 
  !
  ! bring the mode index to cartesian coordinates
  !
  CALL tra_write_zstar(zstareu0_wrk, zstareu, .FALSE.)
  !
  !  symmetrize
  !
  call symtensor ( nat, zstareu )
  !
  ! add the diagonal part
  !
  do ipol = 1, 3
     do na = 1, nat
        zstareu (ipol, ipol, na) = zstareu (ipol, ipol, na) + zv (ityp ( na) )
     enddo
  enddo

  done_zeu=.TRUE.
  CALL summarize_zeu()
  CALL ph_writefile('tensors',0,0,ierr)
  DEALLOCATE ( zstareu0_wrk )

  call stop_clock ('zstar_eu')
  return
end subroutine zstar_eu_tpw
