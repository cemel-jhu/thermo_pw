!
! Copyright (C) 2001-2007 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!

!-----------------------------------------------------------------------
SUBROUTINE apply_ac (ndmx, n, h, ah, ik, m, indi, iflag)
  !-----------------------------------------------------------------------
  !
  ! This routine applies the operator ( H - \epsilon S + alpha_pv P_v)
  ! to a vector h. The result is given in Ah.
  !

  USE kinds,                ONLY : DP
  USE wvfct,                ONLY : npwx, nbnd, current_k
  USE becmod,               ONLY : bec_type, becp, calbec
  USE uspp,                 ONLY : nkb, vkb
  USE fft_base,             ONLY : dffts
  USE wvfct,                ONLY : npwx, et
  USE qpoint,               ONLY : igkq, ikks
  USE noncollin_module,     ONLY : noncolin, npol

  USE control_lr,           ONLY : alpha_pv, nbnd_occ, lgamma
  USE eqv,                  ONLY : evq
  USE qpoint,               ONLY : ikqs
  USE optical,              ONLY : current_w

  USE mp_bands,             ONLY : intra_bgrp_comm
  USE mp,                   ONLY : mp_sum

  !Needed only for TDDFPT
  USE control_flags,        ONLY : gamma_only, tddfpt
  USE wavefunctions,        ONLY : evc

  IMPLICIT NONE

  INTEGER, INTENT(IN) :: ndmx, n, m, ik, iflag, indi(m)
  ! input: the dimension of h
  ! input: the number of bands
  ! input: the k point

  COMPLEX(DP), INTENT(IN)  :: h (npwx*npol, m)
  COMPLEX(DP), INTENT(OUT) :: ah (npwx*npol, m)
  ! input: the vector
  ! output: the operator applied to the vector
  !
  !   local variables
  !
  COMPLEX(DP), ALLOCATABLE :: e (:)
  ! input: the eigenvalue
  INTEGER :: ibnd, ikq, ig
  ! counter on bands
  ! the point k+q
  ! counter on G vetors

  COMPLEX(DP), allocatable :: ps (:,:), hpsi (:,:), spsi (:,:)
  ! scalar products
  ! the product of the Hamiltonian and h
  ! the product of the S matrix and h
  INTEGER, ALLOCATABLE :: ibuf(:)
  COMPLEX(DP) :: iw

  CALL start_clock ('ch_psi')
  IF (ndmx /= npwx*npol) CALL errore('apply_a','something wrong',1)

  ALLOCATE (ps  ( nbnd , m))
  ALLOCATE (e  (m))
  ALLOCATE (hpsi( npwx*npol , m))
  ALLOCATE (spsi( npwx*npol , m))
  hpsi (:,:) = (0.d0, 0.d0)
  spsi (:,:) = (0.d0, 0.d0)
  iw=current_w
  IF (iflag==1) THEN
     DO ibnd=1,m
        e(ibnd) = CMPLX(et(indi(ibnd), ikks(ik))+DREAL(iw), DIMAG(iw), KIND=DP) 
     ENDDO
  ELSE
     DO ibnd=1,m
        e(ibnd) = CMPLX(et(indi(ibnd), ikks(ik))+DREAL(iw),-DIMAG(iw), KIND=DP) 
     ENDDO
  ENDIF
  !
  !   compute the product of the hamiltonian with the h vector
  !
  current_k = ikqs(ik)
  CALL h_psi (npwx, n, m, h, hpsi)
  CALL s_psi (npwx, n, m, h, spsi)


  CALL start_clock ('last')
  !
  !   then we compute the operator H-epsilon S
  !
  ah=(0.d0,0.d0)
  DO ibnd = 1, m
     DO ig = 1, n
        ah (ig, ibnd) = hpsi (ig, ibnd) - e (ibnd) * spsi (ig, ibnd)
     ENDDO
  ENDDO
  IF (noncolin) THEN
     DO ibnd = 1, m
        DO ig = 1, n
           ah (ig+npwx,ibnd)=hpsi(ig+npwx,ibnd)-e(ibnd)*spsi(ig+npwx,ibnd)
        ENDDO
     ENDDO
  ENDIF

  IF (ABS(alpha_pv)>1.D-10) THEN
     IF (gamma_only) THEN
        CALL ch_psi_all_gamma()
     ELSE
        IF (tddfpt) THEN
          ikq = ik
          evq => evc
        ELSE
          ikq = ikqs(ik)
        ENDIF
        CALL ch_psi_all_k()
     ENDIF
  ENDIF

  DEALLOCATE (spsi)
  DEALLOCATE (hpsi)
  DEALLOCATE (e)
  DEALLOCATE (ps)

  IF (tddfpt) NULLIFY(evq)

  CALL stop_clock ('last')
  CALL stop_clock ('ch_psi')
  RETURN
CONTAINS

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!K-point part
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!-----------------------------------------------------------------------
  SUBROUTINE ch_psi_all_k()
!-----------------------------------------------------------------------

    USE becmod, ONLY : becp, calbec
    
    IMPLICIT NONE
    !
    !   Here we compute the projector in the valence band
    !
    ps (:,:) = (0.d0, 0.d0)
    
    IF (noncolin) THEN
       CALL zgemm ('C', 'N', nbnd_occ (ikq) , m, npwx*npol, (1.d0, 0.d0) , evq, &
            npwx*npol, spsi, npwx*npol, (0.d0, 0.d0) , ps, nbnd)
    ELSE
       CALL zgemm ('C', 'N', nbnd_occ (ikq) , m, n, (1.d0, 0.d0) , evq, &
            npwx, spsi, npwx, (0.d0, 0.d0) , ps, nbnd)
    ENDIF
    ps (:,:) = ps(:,:) * alpha_pv
    CALL mp_sum ( ps, intra_bgrp_comm )
    
    hpsi (:,:) = (0.d0, 0.d0)
    IF (noncolin) THEN
       CALL zgemm ('N', 'N', npwx*npol, m, nbnd_occ (ikq) , (1.d0, 0.d0) , evq, &
            npwx*npol, ps, nbnd, (1.d0, 0.d0) , hpsi, npwx*npol)
    ELSE
       CALL zgemm ('N', 'N', n, m, nbnd_occ (ikq) , (1.d0, 0.d0) , evq, &
            npwx, ps, nbnd, (1.d0, 0.d0) , hpsi, npwx)
    END IF
    spsi(:,:) = hpsi(:,:)
    !
    !    And apply S again
    !
    CALL calbec (n, vkb, hpsi, becp, m)
    CALL s_psi (npwx, n, m, hpsi, spsi)
    DO ibnd = 1, m
       DO ig = 1, n
          ah (ig, ibnd) = ah (ig, ibnd) + spsi (ig, ibnd)
       ENDDO
    ENDDO
    IF (noncolin) THEN
       DO ibnd = 1, m
          DO ig = 1, n
             ah (ig+npwx, ibnd) = ah (ig+npwx, ibnd) + spsi (ig+npwx, ibnd)
          ENDDO
       ENDDO
    END IF
    return
  END SUBROUTINE ch_psi_all_k

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!gamma part
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!-----------------------------------------------------------------------
  SUBROUTINE ch_psi_all_gamma()
!-----------------------------------------------------------------------
    
    USE becmod, ONLY : becp,  calbec
    use gvect,                only : gstart

    IMPLICIT NONE

    ps (:,:) = 0.d0
    
    IF (noncolin) THEN
       CALL errore('ch_psi_all', 'non collin in gamma point not implemented',1)
    ELSE
       CALL DGEMM( 'C', 'N', nbnd, m, 2*n, 2.D0,evc, 2*npwx*npol, spsi, 2*npwx*npol, 0.D0, ps, nbnd )
       if(gstart==2) CALL DGER(nbnd, m, -1.0_DP, evc, 2*npwx, spsi, 2*npwx, ps, nbnd )
    ENDIF
    ps (:,:) = ps(:,:) * alpha_pv
    CALL mp_sum ( ps, intra_bgrp_comm )

    hpsi (:,:) = (0.d0, 0.d0)

    IF (noncolin) THEN
       CALL ZGEMM ('N', 'N', npwx*npol, m, nbnd_occ (ik) , (1.d0, 0.d0) , evc, &
            npwx*npol, ps, nbnd, (1.d0, 0.d0) , hpsi, npwx*npol)
    ELSE
       CALL DGEMM ('N', 'N', 2*n, m, nbnd_occ (ik) , 1.d0 , evc, &
            2*npwx, ps, nbnd, 1.d0 , hpsi, 2*npwx)
    ENDIF
    spsi(:,:) = hpsi(:,:)
    !
    !    And apply S again
    !
    CALL calbec (n, vkb, hpsi, becp, m)
    CALL s_psi (npwx, n, m, hpsi, spsi)
    DO ibnd = 1, m
       DO ig = 1, n
          ah (ig, ibnd) = ah (ig, ibnd) + spsi (ig, ibnd)
       ENDDO
    ENDDO
    IF (noncolin) THEN
       DO ibnd = 1, m
          DO ig = 1, n
             ah (ig+npwx, ibnd) = ah (ig+npwx, ibnd) + spsi (ig+npwx, ibnd)
          ENDDO
       ENDDO
    ENDIF
    return
  END SUBROUTINE ch_psi_all_gamma
 
END SUBROUTINE apply_ac
