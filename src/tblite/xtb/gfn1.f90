! This file is part of tblite.
! SPDX-Identifier: LGPL-3.0-or-later
!
! tblite is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! tblite is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with tblite.  If not, see <https://www.gnu.org/licenses/>.

module tblite_xtb_gfn1
   use mctc_env, only : wp
   use mctc_io, only : structure_type
   use tblite_basis_ortho, only : orthogonalize
   use tblite_basis_type, only : basis_type, new_basis, cgto_type
   use tblite_basis_slater, only : slater_to_gauss
   use tblite_classical_halogen, only : new_halogen_correction
   use tblite_coulomb_charge, only : new_effective_coulomb, harmonic_average
   use tblite_coulomb_thirdorder, only : new_onsite_thirdorder
   use tblite_disp, only : d3_dispersion, new_d3_dispersion
   use tblite_ncoord, only : new_ncoord
   use tblite_param_paulingen, only : get_pauling_en
   use tblite_repulsion, only : new_repulsion
   use tblite_xtb_calculator, only : xtb_calculator
   use tblite_xtb_h0, only : new_hamiltonian
   use tblite_xtb_spec, only : tb_h0spec
   implicit none
   private

   public :: new_gfn1_calculator
   public :: gfn1_h0spec

   integer, parameter :: max_elem = 86
   integer, parameter :: max_shell = 3

   !> Use older eV to Eh conversion for consistency
   real(wp), parameter :: evtoau = 1.0_wp / 27.21138505_wp

   !> Exponents of repulsion term for GFN1-xTB repulsion
   real(wp), parameter :: rep_alpha(max_elem) = [&
      & 2.209700_wp, 1.382907_wp, 0.671797_wp, 0.865377_wp, 1.093544_wp, &
      & 1.281954_wp, 1.727773_wp, 2.004253_wp, 2.507078_wp, 3.038727_wp, &
      & 0.704472_wp, 0.862629_wp, 0.929219_wp, 0.948165_wp, 1.067197_wp, &
      & 1.200803_wp, 1.404155_wp, 1.323756_wp, 0.581529_wp, 0.665588_wp, &
      & 0.841357_wp, 0.828638_wp, 1.061627_wp, 0.997051_wp, 1.019783_wp, &
      & 1.137174_wp, 1.188538_wp, 1.399197_wp, 1.199230_wp, 1.145056_wp, &
      & 1.047536_wp, 1.129480_wp, 1.233641_wp, 1.270088_wp, 1.153580_wp, &
      & 1.335287_wp, 0.554032_wp, 0.657904_wp, 0.760144_wp, 0.739520_wp, &
      & 0.895357_wp, 0.944064_wp, 1.028240_wp, 1.066144_wp, 1.131380_wp, &
      & 1.206869_wp, 1.058886_wp, 1.026434_wp, 0.898148_wp, 1.008192_wp, &
      & 0.982673_wp, 0.973410_wp, 0.949181_wp, 1.074785_wp, 0.579919_wp, &
      & 0.606485_wp, 1.311200_wp, 0.839861_wp, 0.847281_wp, 0.854701_wp, &
      & 0.862121_wp, 0.869541_wp, 0.876961_wp, 0.884381_wp, 0.891801_wp, &
      & 0.899221_wp, 0.906641_wp, 0.914061_wp, 0.921481_wp, 0.928901_wp, &
      & 0.936321_wp, 0.853744_wp, 0.971873_wp, 0.992643_wp, 1.132106_wp, &
      & 1.118216_wp, 1.245003_wp, 1.304590_wp, 1.293034_wp, 1.181865_wp, &
      & 0.976397_wp, 0.988859_wp, 1.047194_wp, 1.013118_wp, 0.964652_wp, &
      & 0.998641_wp]

   !> Effective nuclear charge for GFN1-xTB repulsion
   real(wp), parameter :: rep_zeff(max_elem) = [&
      &  1.116244_wp,  0.440231_wp,  2.747587_wp,  4.076830_wp,  4.458376_wp, &
      &  4.428763_wp,  5.498808_wp,  5.171786_wp,  6.931741_wp,  9.102523_wp, &
      & 10.591259_wp, 15.238107_wp, 16.283595_wp, 16.898359_wp, 15.249559_wp, &
      & 15.100323_wp, 17.000000_wp, 17.153132_wp, 20.831436_wp, 19.840212_wp, &
      & 18.676202_wp, 17.084130_wp, 22.352532_wp, 22.873486_wp, 24.160655_wp, &
      & 25.983149_wp, 27.169215_wp, 23.396999_wp, 29.000000_wp, 31.185765_wp, &
      & 33.128619_wp, 35.493164_wp, 36.125762_wp, 32.148852_wp, 35.000000_wp, &
      & 36.000000_wp, 39.653032_wp, 38.924904_wp, 39.000000_wp, 36.521516_wp, &
      & 40.803132_wp, 41.939347_wp, 43.000000_wp, 44.492732_wp, 45.241537_wp, &
      & 42.105527_wp, 43.201446_wp, 49.016827_wp, 51.718417_wp, 54.503455_wp, &
      & 50.757213_wp, 49.215262_wp, 53.000000_wp, 52.500985_wp, 65.029838_wp, &
      & 46.532974_wp, 48.337542_wp, 30.638143_wp, 34.130718_wp, 37.623294_wp, &
      & 41.115870_wp, 44.608445_wp, 48.101021_wp, 51.593596_wp, 55.086172_wp, &
      & 58.578748_wp, 62.071323_wp, 65.563899_wp, 69.056474_wp, 72.549050_wp, &
      & 76.041625_wp, 55.222897_wp, 63.743065_wp, 74.000000_wp, 75.000000_wp, &
      & 76.000000_wp, 77.000000_wp, 78.000000_wp, 79.000000_wp, 80.000000_wp, &
      & 81.000000_wp, 79.578302_wp, 83.000000_wp, 84.000000_wp, 85.000000_wp, &
      & 86.000000_wp]

   !> Atomic hardnesses used in second order electrostatics
   real(wp), parameter :: chemical_hardness(max_elem) = [&
      & 0.470099_wp, 1.441379_wp, 0.205342_wp, 0.274022_wp, 0.340530_wp, &
      & 0.479988_wp, 0.476106_wp, 0.583349_wp, 0.788194_wp, 0.612878_wp, &
      & 0.165908_wp, 0.354151_wp, 0.221658_wp, 0.438331_wp, 0.798319_wp, &
      & 0.643959_wp, 0.519712_wp, 0.529906_wp, 0.114358_wp, 0.134187_wp, &
      & 0.778545_wp, 1.044998_wp, 0.985157_wp, 0.468100_wp, 0.609868_wp, &
      & 0.900000_wp, 0.426680_wp, 0.367019_wp, 0.260192_wp, 0.209459_wp, &
      & 0.193302_wp, 0.800000_wp, 0.732367_wp, 0.714534_wp, 0.732530_wp, &
      & 0.820312_wp, 0.075735_wp, 0.122861_wp, 0.351290_wp, 0.168219_wp, &
      & 0.175875_wp, 0.384677_wp, 0.405474_wp, 0.305394_wp, 0.293973_wp, &
      & 0.280766_wp, 0.472978_wp, 0.130828_wp, 0.132120_wp, 0.480655_wp, &
      & 0.564406_wp, 0.400301_wp, 0.520472_wp, 0.935394_wp, 0.085110_wp, &
      & 0.137819_wp, 0.495969_wp, 0.350000_wp, 0.342306_wp, 0.334612_wp, &
      & 0.326917_wp, 0.319223_wp, 0.311529_wp, 0.303835_wp, 0.296140_wp, &
      & 0.288446_wp, 0.280752_wp, 0.273058_wp, 0.265364_wp, 0.257669_wp, &
      & 0.249975_wp, 0.269977_wp, 0.239696_wp, 0.243663_wp, 0.362512_wp, &
      & 0.354318_wp, 0.290898_wp, 0.370447_wp, 0.496380_wp, 0.334997_wp, &
      & 0.671316_wp, 1.000000_wp, 0.944879_wp, 1.091248_wp, 1.264162_wp, &
      & 0.798170_wp]

   !> Scaling factors for shell electrostatics
   real(wp), parameter :: shell_hardness(0:2, max_elem) = 1.0_wp + reshape([&
      & 0.0_wp, 0.0000000_wp, 0.0000000_wp,  0.0_wp, 0.0000000_wp, 0.0000000_wp, &
      & 0.0_wp,-0.0772012_wp, 0.0000000_wp,  0.0_wp, 0.1113005_wp, 0.0000000_wp, &
      & 0.0_wp, 0.0165643_wp, 0.0000000_wp,  0.0_wp,-0.0471181_wp, 0.0000000_wp, &
      & 0.0_wp, 0.0315090_wp, 0.0000000_wp,  0.0_wp, 0.0374608_wp, 0.0000000_wp, &
      & 0.0_wp,-0.0827352_wp, 0.0000000_wp,  0.0_wp,-0.3892542_wp, 0.0000000_wp, &
      & 0.0_wp,-0.3004391_wp, 0.0000000_wp,  0.0_wp, 0.0674819_wp, 0.0000000_wp, &
      & 0.0_wp, 0.0503564_wp, 0.0000000_wp,  0.0_wp,-0.5925834_wp, 0.0000000_wp, &
      & 0.0_wp,-0.2530875_wp, 0.0000000_wp,  0.0_wp,-0.1678147_wp, 0.0000000_wp, &
      & 0.0_wp,-0.4481841_wp, 0.0000000_wp,  0.0_wp,-0.1450000_wp, 0.0000000_wp, &
      & 0.0_wp,-0.5332978_wp, 0.0000000_wp,  0.0_wp, 1.1522018_wp, 0.0000000_wp, &
      & 0.0_wp,-0.2000000_wp,-0.5934820_wp,  0.0_wp,-0.1500000_wp,-0.7388986_wp, &
      & 0.0_wp,-0.2000000_wp,-0.5229338_wp,  0.0_wp,-0.2500000_wp, 0.0786859_wp, &
      & 0.0_wp,-0.2500000_wp, 1.0544199_wp,  0.0_wp,-0.2000000_wp, 0.1018896_wp, &
      & 0.0_wp,-0.2000000_wp, 0.0222849_wp,  0.0_wp,-0.2000000_wp, 0.1282426_wp, &
      & 0.0_wp, 0.0000000_wp,-0.1290373_wp,  0.0_wp, 0.0200991_wp, 0.0000000_wp, &
      & 0.0_wp,-0.2021175_wp, 0.1000000_wp,  0.0_wp,-0.7631942_wp,-0.1300000_wp, &
      & 0.0_wp,-0.0335509_wp,-0.1000000_wp,  0.0_wp,-0.3213580_wp,-0.2500000_wp, &
      & 0.0_wp,-0.1440020_wp,-0.1000000_wp,  0.0_wp,-0.3743296_wp, 0.0000000_wp, &
      & 0.0_wp,-0.5181667_wp, 0.0000000_wp,  0.0_wp,-0.8003590_wp, 0.0000000_wp, &
      & 0.0_wp,-0.0800000_wp,-0.4159186_wp,  0.0_wp,-0.2500000_wp, 0.0337914_wp, &
      & 0.0_wp,-0.2000000_wp, 0.0638436_wp,  0.0_wp,-0.2500000_wp,-0.3426221_wp, &
      & 0.0_wp,-0.2000000_wp, 0.2642680_wp,  0.0_wp,-0.1500000_wp, 0.1772831_wp, &
      & 0.0_wp,-0.2500000_wp, 0.3782936_wp,  0.0_wp,-0.2500000_wp, 0.3210802_wp, &
      & 0.0_wp,-0.1500000_wp,-0.1477715_wp,  0.0_wp,-0.0775216_wp, 0.0000000_wp, &
      & 0.0_wp, 0.0762515_wp, 0.0000000_wp,  0.0_wp,-0.3444851_wp,-0.1500000_wp, &
      & 0.0_wp,-0.1459812_wp,-0.2000000_wp,  0.0_wp, 0.0137154_wp,-0.2000000_wp, &
      & 0.0_wp,-0.0387987_wp,-0.1500000_wp,  0.0_wp,-0.3435282_wp,-0.1500000_wp, &
      & 0.0_wp,-0.7035550_wp, 0.0000000_wp,  0.0_wp,-0.8801363_wp, 0.0000000_wp, &
      & 0.0_wp,-0.1500000_wp,-0.6396752_wp,  0.0_wp,-0.1500000_wp,-0.5245538_wp, &
      & 0.0_wp,-0.1500000_wp,-0.5064761_wp,  0.0_wp,-0.1500000_wp,-0.4883984_wp, &
      & 0.0_wp,-0.1500000_wp,-0.4703207_wp,  0.0_wp,-0.1500000_wp,-0.4522429_wp, &
      & 0.0_wp,-0.1500000_wp,-0.4341652_wp,  0.0_wp,-0.1500000_wp,-0.4160875_wp, &
      & 0.0_wp,-0.1500000_wp,-0.3980098_wp,  0.0_wp,-0.1500000_wp,-0.3799321_wp, &
      & 0.0_wp,-0.1500000_wp,-0.3618544_wp,  0.0_wp,-0.1500000_wp,-0.3437767_wp, &
      & 0.0_wp,-0.1500000_wp,-0.3256989_wp,  0.0_wp,-0.1500000_wp,-0.3076212_wp, &
      & 0.0_wp,-0.1500000_wp,-0.2895435_wp,  0.0_wp,-0.1500000_wp,-0.1485678_wp, &
      & 0.0_wp,-0.1500000_wp,-0.1870583_wp,  0.0_wp,-0.1500000_wp, 0.0130920_wp, &
      & 0.0_wp,-0.2000000_wp, 0.2507095_wp,  0.0_wp,-0.1000000_wp,-0.0262294_wp, &
      & 0.0_wp,-0.1500000_wp, 0.3805255_wp,  0.0_wp,-0.2000000_wp, 0.0996400_wp, &
      & 0.0_wp,-0.1500000_wp,-0.4380921_wp,  0.0_wp,-0.4204099_wp, 0.0000000_wp, &
      & 0.0_wp,-0.8101017_wp, 0.0000000_wp,  0.0_wp,-0.7925216_wp, 0.0000000_wp, &
      & 0.0_wp,-0.7150589_wp, 0.0000000_wp,  0.0_wp,-0.3955914_wp, 0.0000000_wp, &
      & 0.0_wp,-0.3402676_wp, 0.0000000_wp,  0.0_wp,-0.2380762_wp, 0.0000000_wp],&
      & shape(shell_hardness))

   !> Third order Hubbard derivatives
   real(wp), parameter :: p_hubbard_derivs(max_elem) = [&
      & 0.000000_wp, 1.500000_wp, 1.027370_wp, 0.900554_wp, 1.300000_wp, &
      & 1.053856_wp, 0.042507_wp,-0.005102_wp, 1.615037_wp, 1.600000_wp, &
      & 1.200000_wp, 1.100000_wp, 1.200000_wp, 1.500000_wp, 1.500000_wp, &
      & 1.500000_wp, 1.000000_wp, 0.829312_wp, 0.732923_wp, 1.116963_wp, &
      & 1.000000_wp, 0.739203_wp, 0.800000_wp, 0.800000_wp, 0.300000_wp, &
      & 0.500000_wp, 0.300000_wp, 1.000000_wp, 0.237602_wp, 1.400000_wp, &
      & 1.400000_wp, 1.400000_wp, 1.300000_wp, 1.300000_wp,-0.500000_wp, &
      & 1.000000_wp, 1.500000_wp, 1.300000_wp, 1.400000_wp, 0.581478_wp, &
      & 0.280147_wp, 0.041052_wp, 0.500000_wp, 0.001205_wp, 0.622690_wp, &
      & 0.500000_wp,-0.445675_wp, 1.362587_wp, 1.063557_wp,-0.321283_wp, &
      &-0.341503_wp, 0.894388_wp,-0.500000_wp,-0.800000_wp, 1.500000_wp, &
      & 1.500000_wp, 1.500000_wp, 1.200000_wp, 1.200000_wp, 1.200000_wp, &
      & 1.200000_wp, 1.200000_wp, 1.200000_wp, 1.200000_wp, 1.200000_wp, &
      & 1.200000_wp, 1.200000_wp, 1.200000_wp, 1.200000_wp, 1.200000_wp, &
      & 1.200000_wp, 0.847011_wp, 0.064592_wp,-0.014599_wp, 0.300000_wp, &
      &-0.170295_wp, 0.965726_wp, 1.092759_wp, 0.123512_wp,-0.267745_wp, &
      & 0.936157_wp, 1.500000_wp, 0.877488_wp,-0.035874_wp,-0.860502_wp, &
      &-0.838429_wp] * 0.1_wp

   !> Number of shells
   integer, parameter :: nshell(max_elem) = [&
      & 2, 1, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2, 3, 3, 3, 3, 3, 3, 2, 3, &
      & 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 3, 3, 3, 3, 3, 3, 2, 3, 3, 3, &
      & 3, 3, 3, 3, 3, 3, 3, 2, 3, 3, 3, 3, 3, 3, 2, 3, 3, 3, 3, 3, &
      & 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, &
      & 2, 2, 2, 3, 3, 3]

   !> Angular momentum of each shell
   integer, parameter :: ang_shell(max_shell, max_elem) = reshape([&
      & 0, 0, 0,  0, 0, 0,  0, 1, 0,  0, 1, 0,  0, 1, 0,  0, 1, 0,  0, 1, 0, &
      & 0, 1, 0,  0, 1, 0,  0, 1, 2,  0, 1, 0,  0, 1, 0,  0, 1, 2,  0, 1, 2, &
      & 0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 0,  0, 1, 2,  2, 0, 1, &
      & 2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1, &
      & 2, 0, 1,  0, 1, 0,  0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 2, &
      & 0, 1, 2,  0, 1, 0,  0, 1, 2,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1, &
      & 2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  0, 1, 0,  0, 1, 2, &
      & 0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 2,  0, 1, 0,  0, 1, 2, &
      & 2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1, &
      & 2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1, &
      & 2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1,  2, 0, 1, &
      & 2, 0, 1,  2, 0, 1,  0, 1, 0,  0, 1, 0,  0, 1, 0,  0, 1, 0,  0, 1, 2, &
      & 0, 1, 2,  0, 1, 2], shape(ang_shell))

   !> Principal quantum number of each shell
   integer, parameter :: principal_quantum_number(max_shell, max_elem) = reshape([&
      & 1, 2, 0,  1, 0, 0,  2, 2, 0,  2, 2, 0,  2, 2, 0,  2, 2, 0,  2, 2, 0, &
      & 2, 2, 0,  2, 2, 0,  2, 2, 3,  3, 3, 0,  3, 3, 0,  3, 3, 3,  3, 3, 3, &
      & 3, 3, 3,  3, 3, 3,  3, 3, 3,  3, 3, 3,  4, 4, 0,  4, 4, 3,  3, 4, 4, &
      & 3, 4, 4,  3, 4, 4,  3, 4, 4,  3, 4, 4,  3, 4, 4,  3, 4, 4,  3, 4, 4, &
      & 3, 4, 4,  4, 4, 0,  4, 4, 4,  4, 4, 4,  4, 4, 4,  4, 4, 4,  4, 4, 4, &
      & 4, 4, 4,  5, 5, 0,  5, 5, 4,  4, 5, 5,  4, 5, 5,  4, 5, 5,  4, 5, 5, &
      & 4, 5, 5,  4, 5, 5,  4, 5, 5,  4, 5, 5,  4, 5, 5,  5, 5, 0,  5, 5, 5, &
      & 5, 5, 5,  5, 5, 5,  5, 5, 5,  5, 5, 5,  5, 5, 5,  5, 5, 0,  5, 5, 4, &
      & 5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6, &
      & 5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6, &
      & 5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6,  5, 6, 6, &
      & 5, 6, 6,  5, 6, 6,  6, 6, 0,  6, 6, 0,  6, 6, 0,  6, 6, 0,  6, 6, 5, &
      & 6, 6, 5,  6, 6, 5], shape(principal_quantum_number))

   !> Shell polynomials to scale Hamiltonian elements
   real(wp), parameter :: p_shpoly(0:2, max_elem) = reshape([&
      &  0.000000_wp,  0.000000_wp,  0.000000_wp,  8.084149_wp,  0.000000_wp,  0.000000_wp, &
      & -4.102845_wp,  9.259276_wp,  0.000000_wp,-12.991482_wp, -1.308797_wp,  0.000000_wp, &
      & -7.088823_wp,  0.655877_wp,  0.000000_wp, -7.082170_wp,  0.812216_wp,  0.000000_wp, &
      &-12.745585_wp, -1.428367_wp,  0.000000_wp,-13.729047_wp, -4.453341_wp,  0.000000_wp, &
      & -3.921613_wp,-11.422491_wp,  0.000000_wp, -2.115896_wp,-15.124326_wp,  0.000000_wp, &
      & 13.188489_wp, 10.969376_wp,  0.000000_wp,-19.219408_wp, 18.272922_wp,  0.000000_wp, &
      &-21.085827_wp, 24.805127_wp, 26.405814_wp,-14.201582_wp, -3.893343_wp, 25.499221_wp, &
      &-16.118985_wp, -2.241189_wp, 30.984577_wp,-16.989922_wp, -6.067779_wp, 16.248395_wp, &
      & -9.341919_wp, -8.499805_wp, 13.088867_wp, -0.082808_wp, -9.217948_wp, 12.204172_wp, &
      & 12.482844_wp, 22.323655_wp,  0.000000_wp,-11.421376_wp, 14.628284_wp, 10.129602_wp, &
      &  9.522966_wp, 44.183320_wp,-36.027863_wp, 24.879987_wp, 18.910954_wp,-24.908650_wp, &
      & -5.301066_wp, 22.945047_wp,-29.197847_wp, -2.432193_wp, 11.274054_wp,-22.608167_wp, &
      &  1.025345_wp,  1.834626_wp,-25.016650_wp, -2.182723_wp, 11.769535_wp,-22.920815_wp, &
      &  0.815250_wp, 15.765732_wp,-21.678930_wp, 15.160508_wp, 15.782685_wp,-26.348820_wp, &
      & -3.590501_wp,  7.413473_wp,-21.142399_wp,-15.535695_wp,  4.061664_wp,  0.000000_wp, &
      &-14.584657_wp,  9.375082_wp, 19.671655_wp,-12.195371_wp,-11.374296_wp,  9.364108_wp, &
      &-17.489686_wp, -6.747956_wp, 17.858510_wp,-14.852299_wp, -9.863477_wp,  9.556181_wp, &
      &-17.815502_wp,-14.058044_wp,  5.468245_wp,-25.437273_wp,-12.813227_wp, 10.440712_wp, &
      & -7.450752_wp, 16.670533_wp,  0.000000_wp, -6.087125_wp,  2.115262_wp, 17.076466_wp, &
      & 10.950764_wp, 45.679760_wp,-28.061976_wp, 44.110231_wp, 25.863572_wp,-22.240873_wp, &
      & 15.379439_wp, 30.159730_wp,-25.998052_wp,  5.815301_wp, 14.527159_wp,-22.556077_wp, &
      & 24.977603_wp,  1.953838_wp,-23.231470_wp, 15.281981_wp,  1.340798_wp,-23.099524_wp, &
      & 10.450086_wp, 15.559547_wp,-23.540560_wp, 17.475085_wp, 21.621321_wp,-23.290322_wp, &
      &-12.856324_wp,  0.187155_wp, -6.963262_wp,-10.281188_wp,  6.247124_wp,  0.000000_wp, &
      &-10.488459_wp, 19.136222_wp,  5.584366_wp,-19.310676_wp, -5.460959_wp, 10.683419_wp, &
      &-17.310388_wp, -7.203718_wp, 10.096015_wp,-17.836704_wp, -9.887978_wp, 20.942979_wp, &
      &-21.954071_wp,-10.823970_wp, 12.522287_wp,-22.530281_wp,-16.667114_wp,  8.021956_wp, &
      & -1.460631_wp, 15.879494_wp,  0.000000_wp, -5.468018_wp,  4.368854_wp, 14.328052_wp, &
      & -3.988102_wp, 40.847293_wp,-44.208463_wp,  6.148475_wp, 42.873822_wp,-36.440945_wp, &
      &  7.806576_wp, 42.846148_wp,-36.021673_wp,  9.464678_wp, 42.818474_wp,-35.602402_wp, &
      & 11.122779_wp, 42.790801_wp,-35.183130_wp, 12.780881_wp, 42.763127_wp,-34.763859_wp, &
      & 14.438982_wp, 42.735454_wp,-34.344587_wp, 16.097083_wp, 42.707780_wp,-33.925315_wp, &
      & 17.755185_wp, 42.680106_wp,-33.506044_wp, 19.413286_wp, 42.652433_wp,-33.086772_wp, &
      & 21.071387_wp, 42.624759_wp,-32.667501_wp, 22.729489_wp, 42.597085_wp,-32.248229_wp, &
      & 24.387590_wp, 42.569412_wp,-31.828957_wp, 26.045692_wp, 42.541738_wp,-31.409686_wp, &
      & 27.703793_wp, 42.514065_wp,-30.990414_wp, 15.014122_wp, 22.898249_wp,-21.116286_wp, &
      & 29.782424_wp, 36.420564_wp,-23.077812_wp, 35.195571_wp, 18.760746_wp,-17.030630_wp, &
      & 23.560994_wp, -0.067497_wp,-23.115824_wp, 24.928002_wp, -4.330556_wp,-19.564083_wp, &
      & 25.774929_wp, -0.704597_wp,-21.172493_wp, 38.415536_wp, -0.665483_wp,-22.169385_wp, &
      &-11.443658_wp, -5.119735_wp,-11.067532_wp, -6.581368_wp,  3.995243_wp,  0.000000_wp, &
      & -2.193199_wp,  0.060451_wp,  0.000000_wp,-10.874138_wp, -6.034796_wp,  0.000000_wp, &
      &-20.410234_wp, -9.424568_wp,  0.000000_wp,-18.477865_wp,-14.037423_wp, 13.809093_wp, &
      &-21.965390_wp,-12.804436_wp, 16.836546_wp,-22.139701_wp,-20.539955_wp, 17.249637_wp],&
      & shape(p_shpoly)) * 0.01_wp

   !> Reference occupation of the atom
   real(wp), parameter :: reference_occ(0:2, max_elem) = reshape([&
      & 1.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 0.0_wp,  1.0_wp, 0.0_wp, 0.0_wp, &
      & 2.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 1.0_wp, 0.0_wp,  2.0_wp, 2.0_wp, 0.0_wp, &
      & 2.0_wp, 3.0_wp, 0.0_wp,  2.0_wp, 4.0_wp, 0.0_wp,  2.0_wp, 5.0_wp, 0.0_wp, &
      & 2.0_wp, 6.0_wp, 0.0_wp,  1.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 0.0_wp, &
      & 2.0_wp, 1.0_wp, 0.0_wp,  2.0_wp, 2.0_wp, 0.0_wp,  2.0_wp, 3.0_wp, 0.0_wp, &
      & 2.0_wp, 4.0_wp, 0.0_wp,  2.0_wp, 5.0_wp, 0.0_wp,  2.0_wp, 6.0_wp, 0.0_wp, &
      & 1.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 2.0_wp,  2.0_wp, 0.0_wp, 3.0_wp,  2.0_wp, 0.0_wp, 4.0_wp, &
      & 2.0_wp, 0.0_wp, 5.0_wp,  2.0_wp, 0.0_wp, 6.0_wp,  2.0_wp, 0.0_wp, 7.0_wp, &
      & 2.0_wp, 0.0_wp, 8.0_wp,  2.0_wp, 0.0_wp, 9.0_wp,  2.0_wp, 0.0_wp, 0.0_wp, &
      & 2.0_wp, 1.0_wp, 0.0_wp,  2.0_wp, 2.0_wp, 0.0_wp,  2.0_wp, 3.0_wp, 0.0_wp, &
      & 2.0_wp, 4.0_wp, 0.0_wp,  2.0_wp, 5.0_wp, 0.0_wp,  2.0_wp, 6.0_wp, 0.0_wp, &
      & 1.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 2.0_wp,  2.0_wp, 0.0_wp, 3.0_wp,  2.0_wp, 0.0_wp, 4.0_wp, &
      & 2.0_wp, 0.0_wp, 5.0_wp,  2.0_wp, 0.0_wp, 6.0_wp,  2.0_wp, 0.0_wp, 7.0_wp, &
      & 2.0_wp, 0.0_wp, 8.0_wp,  2.0_wp, 0.0_wp, 9.0_wp,  2.0_wp, 0.0_wp, 0.0_wp, &
      & 2.0_wp, 1.0_wp, 0.0_wp,  2.0_wp, 2.0_wp, 0.0_wp,  2.0_wp, 3.0_wp, 0.0_wp, &
      & 2.0_wp, 4.0_wp, 0.0_wp,  2.0_wp, 5.0_wp, 0.0_wp,  2.0_wp, 6.0_wp, 0.0_wp, &
      & 1.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp, &
      & 2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 1.0_wp,  2.0_wp, 0.0_wp, 2.0_wp, &
      & 2.0_wp, 0.0_wp, 3.0_wp,  2.0_wp, 0.0_wp, 4.0_wp,  2.0_wp, 0.0_wp, 5.0_wp, &
      & 2.0_wp, 0.0_wp, 6.0_wp,  2.0_wp, 0.0_wp, 7.0_wp,  2.0_wp, 0.0_wp, 8.0_wp, &
      & 2.0_wp, 0.0_wp, 9.0_wp,  2.0_wp, 0.0_wp, 0.0_wp,  2.0_wp, 1.0_wp, 0.0_wp, &
      & 2.0_wp, 2.0_wp, 0.0_wp,  2.0_wp, 3.0_wp, 0.0_wp,  2.0_wp, 4.0_wp, 0.0_wp, &
      & 2.0_wp, 5.0_wp, 0.0_wp,  2.0_wp, 6.0_wp, 0.0_wp], shape(reference_occ))

   !> Exponent of the Slater function
   real(wp), parameter :: slater_exponent(max_shell, max_elem) = reshape([&
      & 1.207940_wp,1.993207_wp,0.000000_wp, 2.133698_wp,0.000000_wp,0.000000_wp, &
      & 0.743881_wp,0.541917_wp,0.000000_wp, 0.876888_wp,1.104598_wp,0.000000_wp, &
      & 1.667617_wp,1.495078_wp,0.000000_wp, 1.960324_wp,1.832096_wp,0.000000_wp, &
      & 2.050067_wp,2.113682_wp,0.000000_wp, 2.345365_wp,2.153060_wp,0.000000_wp, &
      & 2.968015_wp,2.256959_wp,0.000000_wp, 3.200000_wp,2.294365_wp,2.684436_wp, &
      & 0.819143_wp,0.628961_wp,0.000000_wp, 1.271287_wp,0.797143_wp,0.000000_wp, &
      & 1.497753_wp,1.232966_wp,0.606937_wp, 1.521960_wp,1.609138_wp,1.168971_wp, &
      & 1.993165_wp,1.826973_wp,1.293345_wp, 2.506934_wp,1.992775_wp,1.964867_wp, &
      & 2.847946_wp,2.077534_wp,1.932463_wp, 3.502323_wp,2.287983_wp,1.761181_wp, &
      & 0.841791_wp,0.771618_wp,0.000000_wp, 1.321845_wp,0.734954_wp,0.947032_wp, &
      & 2.200000_wp,1.532191_wp,1.017366_wp, 1.941479_wp,1.477526_wp,1.063921_wp, &
      & 1.812440_wp,1.345487_wp,1.100000_wp, 1.915482_wp,1.241910_wp,1.130000_wp, &
      & 2.016302_wp,1.882798_wp,1.270000_wp, 2.264485_wp,1.382959_wp,1.300000_wp, &
      & 2.279966_wp,1.925082_wp,1.350000_wp, 2.356745_wp,1.532263_wp,1.350000_wp, &
      & 2.598287_wp,1.583677_wp,1.350000_wp, 1.722526_wp,1.061945_wp,0.000000_wp, &
      & 1.992354_wp,1.482052_wp,0.712761_wp, 2.172951_wp,1.794495_wp,0.769997_wp, &
      & 2.265106_wp,1.986411_wp,1.113511_wp, 3.044672_wp,2.098532_wp,1.863317_wp, &
      & 2.886237_wp,2.190987_wp,1.789395_wp, 2.828105_wp,1.965472_wp,1.512609_wp, &
      & 0.809529_wp,0.950253_wp,0.000000_wp, 1.458742_wp,0.730658_wp,1.028147_wp, &
      & 2.300000_wp,1.593058_wp,1.170000_wp, 2.175661_wp,1.665905_wp,1.230000_wp, &
      & 2.092288_wp,1.459971_wp,1.200000_wp, 1.891236_wp,1.827996_wp,1.220000_wp, &
      & 2.120497_wp,1.789115_wp,1.250000_wp, 2.352683_wp,1.883645_wp,1.370000_wp, &
      & 2.436353_wp,2.000000_wp,1.470000_wp, 2.528954_wp,2.073217_wp,1.550000_wp, &
      & 2.720329_wp,1.994885_wp,1.620000_wp, 1.980518_wp,1.191810_wp,0.000000_wp, &
      & 2.226101_wp,1.625926_wp,0.663076_wp, 2.474055_wp,1.893755_wp,1.547485_wp, &
      & 2.761687_wp,2.076379_wp,1.071094_wp, 2.880945_wp,2.254863_wp,1.724516_wp, &
      & 3.117622_wp,2.248195_wp,1.831809_wp, 3.128524_wp,2.316580_wp,1.888452_wp, &
      & 0.779877_wp,0.810404_wp,0.000000_wp, 1.387083_wp,0.532658_wp,0.853415_wp, &
      & 3.000000_wp,1.492677_wp,1.350000_wp, 3.000000_wp,1.553483_wp,1.380859_wp, &
      & 2.992307_wp,1.578839_wp,1.385620_wp, 2.984614_wp,1.604196_wp,1.390381_wp, &
      & 2.976922_wp,1.629552_wp,1.395142_wp, 2.969229_wp,1.654909_wp,1.399903_wp, &
      & 2.961536_wp,1.680265_wp,1.404664_wp, 2.953843_wp,1.705622_wp,1.409425_wp, &
      & 2.946150_wp,1.730979_wp,1.414186_wp, 2.938457_wp,1.756335_wp,1.418947_wp, &
      & 2.930765_wp,1.781692_wp,1.423708_wp, 2.923072_wp,1.807048_wp,1.428469_wp, &
      & 2.915379_wp,1.832405_wp,1.433230_wp, 2.907686_wp,1.857761_wp,1.437991_wp, &
      & 2.899993_wp,1.883118_wp,1.442752_wp, 2.466693_wp,2.039390_wp,1.450000_wp, &
      & 2.177327_wp,1.692963_wp,1.400000_wp, 2.300752_wp,2.096013_wp,1.400000_wp, &
      & 2.470782_wp,2.220548_wp,1.450000_wp, 2.734340_wp,2.365840_wp,1.650000_wp, &
      & 2.797508_wp,2.274300_wp,1.650000_wp, 2.807068_wp,2.341428_wp,1.650000_wp, &
      & 3.117733_wp,2.325119_wp,1.750000_wp, 2.062597_wp,1.721925_wp,0.000000_wp, &
      & 2.647541_wp,1.717991_wp,0.000000_wp, 2.847707_wp,2.068091_wp,0.000000_wp, &
      & 2.895660_wp,2.256279_wp,0.000000_wp, 3.150662_wp,2.382063_wp,1.241625_wp, &
      & 3.516922_wp,2.392024_wp,1.380239_wp, 3.520683_wp,2.535389_wp,1.418875_wp],&
      & shape(slater_exponent))

   !> Atomic level information
   real(wp), parameter :: p_selfenergy(max_shell, max_elem) = reshape([&
      &-10.923452_wp, -2.171902_wp,  0.000000_wp,-22.121015_wp,  0.000000_wp,  0.000000_wp, &
      & -7.270105_wp, -4.609277_wp,  0.000000_wp, -9.541494_wp, -5.812621_wp,  0.000000_wp, &
      &-12.497913_wp, -7.604923_wp,  0.000000_wp,-13.587210_wp,-10.052785_wp,  0.000000_wp, &
      &-20.058000_wp,-12.889326_wp,  0.000000_wp,-23.398376_wp,-17.886554_wp,  0.000000_wp, &
      &-24.776175_wp,-17.274415_wp,  0.000000_wp,-31.167487_wp,-18.268975_wp,  1.487984_wp, &
      & -4.717569_wp, -2.797054_wp,  0.000000_wp, -9.970921_wp, -2.901013_wp,  0.000000_wp, &
      &-12.916245_wp, -3.441043_wp, -1.751415_wp,-14.506128_wp, -7.557337_wp, -2.508113_wp, &
      &-18.865587_wp, -9.386464_wp, -0.673989_wp,-23.819013_wp,-12.120136_wp, -1.711261_wp, &
      &-24.452163_wp,-12.883714_wp, -1.190095_wp,-31.395427_wp,-17.412901_wp, -1.119399_wp, &
      & -5.815562_wp, -3.747255_wp,  0.000000_wp, -7.979180_wp, -2.517008_wp, -2.752355_wp, &
      & -7.172021_wp, -9.632943_wp, -0.696628_wp, -7.617343_wp, -7.948161_wp, -0.902143_wp, &
      & -6.677563_wp, -9.000000_wp, -0.108008_wp, -7.357172_wp, -7.024438_wp, -3.933133_wp, &
      & -8.558648_wp, -6.149482_wp, -4.360801_wp, -9.705009_wp, -6.617863_wp, -4.595985_wp, &
      &-10.285239_wp, -4.593686_wp, -3.855768_wp,-10.841022_wp, -8.687611_wp, -3.332933_wp, &
      &-11.114050_wp, -8.373193_wp, -4.419045_wp,-11.263459_wp, -4.666731_wp,  0.000000_wp, &
      &-13.273222_wp, -4.859478_wp, -2.245112_wp,-12.558286_wp, -8.035796_wp, -2.752271_wp, &
      &-17.515251_wp, -8.272706_wp, -1.245776_wp,-23.000000_wp,-10.398968_wp, -0.821804_wp, &
      &-19.875752_wp,-12.818655_wp, -3.348113_wp,-20.280017_wp,-15.200155_wp, -4.253986_wp, &
      & -7.616948_wp, -4.369842_wp,  0.000000_wp, -6.840171_wp, -3.338573_wp, -1.715680_wp, &
      & -5.731066_wp, -8.748292_wp, -0.838555_wp, -6.771010_wp, -3.979156_wp, -3.954049_wp, &
      & -9.245726_wp, -9.268975_wp, -1.348707_wp, -8.176239_wp, -7.645737_wp, -3.802884_wp, &
      & -8.690050_wp, -5.089073_wp, -4.878724_wp,-10.960165_wp, -6.304229_wp, -5.569969_wp, &
      &-11.935915_wp, -4.883179_wp, -4.427854_wp,-12.059626_wp, -5.724219_wp, -2.575000_wp, &
      & -9.675945_wp, -5.723081_wp, -3.273430_wp,-12.099216_wp, -3.859493_wp,  0.000000_wp, &
      &-16.894094_wp, -3.502771_wp, -3.650350_wp,-24.164818_wp, -7.640096_wp, -1.908531_wp, &
      &-20.650528_wp, -7.536020_wp, -2.185884_wp,-29.899753_wp,-10.026096_wp, -0.372055_wp, &
      &-23.832631_wp,-11.604442_wp, -2.025327_wp,-21.969064_wp,-11.870978_wp, -2.697796_wp, &
      & -6.341379_wp, -3.944275_wp,  0.000000_wp, -6.452630_wp, -3.975353_wp, -2.305768_wp, &
      & -5.872226_wp, -6.500000_wp, -0.727921_wp, -5.032003_wp, -6.275363_wp,  0.291196_wp, &
      & -4.944984_wp, -6.271128_wp,  0.241817_wp, -4.857964_wp, -6.266893_wp,  0.192438_wp, &
      & -4.770945_wp, -6.262657_wp,  0.143059_wp, -4.683925_wp, -6.258422_wp,  0.093680_wp, &
      & -4.596906_wp, -6.254187_wp,  0.044301_wp, -4.509886_wp, -6.249952_wp, -0.005078_wp, &
      & -4.422867_wp, -6.245716_wp, -0.054457_wp, -4.335848_wp, -6.241481_wp, -0.103836_wp, &
      & -4.248828_wp, -6.237246_wp, -0.153215_wp, -4.161809_wp, -6.233011_wp, -0.202593_wp, &
      & -4.074789_wp, -6.228775_wp, -0.251972_wp, -3.987770_wp, -6.224540_wp, -0.301351_wp, &
      & -3.900750_wp, -6.220305_wp, -0.350730_wp, -4.360558_wp, -5.910623_wp, -2.814338_wp, &
      & -9.232014_wp, -8.600553_wp, -0.252865_wp, -8.997799_wp, -2.878936_wp, -3.369287_wp, &
      & -7.858164_wp, -6.430285_wp, -5.165147_wp,-10.716969_wp, -3.655133_wp, -7.060522_wp, &
      &-12.054598_wp, -5.686006_wp, -6.208990_wp,-11.571582_wp, -7.184794_wp, -5.080419_wp, &
      &-10.047575_wp, -6.530840_wp, -3.296026_wp,-12.452637_wp, -4.169731_wp,  0.000000_wp, &
      &-12.563376_wp, -5.131043_wp,  0.000000_wp,-14.496335_wp, -5.848584_wp,  0.000000_wp, &
      &-18.199529_wp, -6.735929_wp,  0.000000_wp,-23.908422_wp, -8.889548_wp, -0.921251_wp, &
      &-21.752193_wp,-10.031093_wp, -0.852571_wp,-18.381647_wp,-10.236606_wp, -0.973687_wp],&
      & shape(p_selfenergy)) * evtoau

   integer, parameter :: gfn1_kinds(max_elem) = [&
      &  1,                                                 1, &! H-He
      &  0, 0,                               0, 1, 1, 1, 1, 1, &! Li-Ne
      &  0, 0,                               0, 1, 1, 1, 1, 1, &! Na-Ar
      &  0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, &! K-Kr
      &  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, &! Rb-Xe
      &  0, 0, &! Cs/Ba
      &        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, &!La-Lu
      &        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1]  ! Lu-Rn

   !> Scaling factor of the atomic radii
   real(wp), parameter :: halogen_radscale = 1.3_wp

   !> Damping parameter for the halogen bond interactions
   real(wp), parameter :: halogen_damping = 0.44_wp

   !> Strength of the halogen bond
   real(wp), parameter :: halogen_bond(1:max_elem) = 0.1_wp * [ &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.381742_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.321944_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, &
      & 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.000000_wp, 0.220000_wp, &
      & 0.000000_wp]

   !> Specification of the GFN1-xTB effective Hamiltonian
   type, extends(tb_h0spec) :: gfn1_h0spec
      real(wp) :: kshell(0:2, 0:2)
      real(wp), allocatable :: kpair(:, :)
      logical, allocatable :: valence(:, :)
   contains
      !> Generator for the self energy / atomic levels of the Hamiltonian
      procedure :: get_selfenergy
      !> Generator for the coordination number dependent shift of the self energy
      procedure :: get_cnshift
      !> Generator for the enhancement factor to for scaling Hamiltonian elements
      procedure :: get_hscale
      !> Generator for the polynomial parameters for the distant dependent scaling
      procedure :: get_shpoly
      !> Generator for the reference occupation numbers of the atoms
      procedure :: get_reference_occ
   end type gfn1_h0spec

   interface gfn1_h0spec
      module procedure :: new_gfn1_h0spec
   end interface gfn1_h0spec

contains


subroutine new_gfn1_calculator(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(out) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   call add_basis(calc, mol)
   call add_ncoord(calc, mol)
   call add_hamiltonian(calc, mol)
   call add_repulsion(calc, mol)
   call add_dispersion(calc, mol)
   call add_coulomb(calc, mol)
   call add_halogen(calc, mol)

end subroutine new_gfn1_calculator

subroutine add_basis(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   integer :: isp, izp, ish, stat, ng, il
   integer, allocatable :: nsh_id(:)
   integer :: ang_idx(0:2), ortho(max_shell)
   type(cgto_type), allocatable :: cgto(:, :)

   nsh_id = nshell(mol%num)
   allocate(cgto(maxval(nsh_id), mol%nid))
   do isp = 1, mol%nid
      ang_idx = 0
      ortho = 0
      izp = mol%num(isp)
      do ish = 1, nsh_id(isp)
         il = ang_shell(ish, izp)
         ng = number_of_primitives(ish, izp, ang_idx(il) == 0)
         if (ang_idx(il) > 0) then
            ortho(ish) = ang_idx(il)
         else
            ang_idx(il) = ish
         end if
         call slater_to_gauss(ng, principal_quantum_number(ish, izp), il, &
            & slater_exponent(ish, izp), cgto(ish, isp), .true., stat)
      end do

      do ish = 1, nsh_id(isp)
         if (ortho(ish) > 0) then
            call orthogonalize(cgto(ortho(ish), isp), cgto(ish, isp))
         end if
      end do
   end do

   call new_basis(calc%bas, mol, nsh_id, cgto, 1.0_wp)

end subroutine add_basis

pure function number_of_primitives(ish, izp, valence) result(nprim)
   integer, intent(in) :: ish
   integer, intent(in) :: izp
   logical, intent(in) :: valence
   integer :: nprim

   nprim = 0
   if (izp <= 2) then
      select case(ang_shell(ish, izp))
      case(0)
         nprim = merge(4, 3, valence)
      case(1:)
         nprim = 3
      end select
   else
      select case(ang_shell(ish, izp))
      case(0)
         nprim = merge(6, 3, principal_quantum_number(ish, izp) > 5 .or. valence)
      case(1)
         nprim = 6
      case(2:)
         nprim = 4
      end select
   end if

end function number_of_primitives

subroutine add_hamiltonian(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   call new_hamiltonian(calc%h0, mol, calc%bas, new_gfn1_h0spec(mol))
end subroutine add_hamiltonian

subroutine add_dispersion(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   real(wp), parameter :: s6 = 1.0_wp, s8 = 2.4_wp, a1 = 0.63_wp, a2 = 5.0_wp, s9 = 0.0_wp
   type(d3_dispersion), allocatable :: tmp

   allocate(tmp)
   call new_d3_dispersion(tmp, mol, s6=s6, s8=s8, a1=a1, a2=a2, s9=s9)
   call move_alloc(tmp, calc%dispersion)
end subroutine add_dispersion

subroutine add_ncoord(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   call new_ncoord(calc%ncoord, mol, cn_type="exp")
end subroutine add_ncoord

subroutine add_repulsion(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   real(wp), allocatable :: alpha(:), zeff(:)

   allocate(calc%repulsion)
   alpha = rep_alpha(mol%num)
   zeff = rep_zeff(mol%num)
   call new_repulsion(calc%repulsion, mol, alpha, zeff, 1.5_wp, 1.5_wp, 1.0_wp)
end subroutine add_repulsion

subroutine add_coulomb(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   real(wp), allocatable :: hardness(:, :), hubbard_derivs(:, :)

   allocate(calc%coulomb)
   allocate(calc%coulomb%es2)
   call get_shell_hardness(mol, calc%bas, hardness)
   call new_effective_coulomb(calc%coulomb%es2, mol, 2.0_wp, hardness, harmonic_average, &
      & calc%bas%nsh_id)

   allocate(calc%coulomb%es3)
   hubbard_derivs = spread(p_hubbard_derivs(mol%num), 1, 1)
   call new_onsite_thirdorder(calc%coulomb%es3, mol, hubbard_derivs)

end subroutine add_coulomb

subroutine get_shell_hardness(mol, bas, hardness)
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Shell resolved hardness parameters
   real(wp), allocatable, intent(out) :: hardness(:, :)

   integer :: isp, izp, ish, il

   allocate(hardness(maxval(bas%nsh_id), mol%nid))
   hardness(:, :) = 0.0_wp
   do isp = 1, mol%nid
      izp = mol%num(isp)
      do ish = 1, bas%nsh_id(isp)
         il = bas%cgto(ish, isp)%ang
         hardness(ish, isp) = chemical_hardness(izp) * shell_hardness(il, izp)
      end do
   end do
end subroutine get_shell_hardness

subroutine add_halogen(calc, mol)
   !> Instance of the xTB evaluator
   type(xtb_calculator), intent(inout) :: calc
   !> Molecular structure data
   type(structure_type), intent(in) :: mol

   real(wp), allocatable :: bond_strength(:)

   allocate(calc%halogen)
   bond_strength = halogen_bond(mol%num)
   call new_halogen_correction(calc%halogen, mol, halogen_damping, halogen_radscale, &
      & bond_strength)
end subroutine add_halogen


pure function new_gfn1_h0spec(mol) result(self)
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Instance of the Hamiltonian specification
   type(gfn1_h0spec) :: self

   real(wp), parameter :: kshell(0:2) = [1.85_wp, 2.25_wp, 2.0_wp]
   integer :: isp, jsp, il, jl, izp, ish
   integer :: ang_idx(0:2)

   allocate(self%kpair(mol%nid, mol%nid))
   do isp = 1, mol%nid
      do jsp = 1, mol%nid
         self%kpair(jsp, isp) = get_pair_param(mol%num(jsp), mol%num(isp))
      end do
   end do

   do il = 0, 2
      do jl = 0, 2
         self%kshell(jl, il) = 0.5_wp * (kshell(jl) + kshell(il))
      end do
   end do
   self%kshell(0, 1) = 2.08_wp
   self%kshell(1, 0) = 2.08_wp

   allocate(self%valence(3, mol%nid))
   do isp = 1, mol%nid
      ang_idx = 0
      izp = mol%num(isp)
      do ish = 1, nshell(izp)
         il = ang_shell(ish, izp)
         self%valence(ish, isp) = ang_idx(il) == 0
         if (self%valence(ish, isp)) ang_idx(il) = ish
      end do
   end do

end function new_gfn1_h0spec

pure function get_pair_param(jzp, izp) result(kpair)
   integer, intent(in) :: izp, jzp
   real(wp) :: kpair
   integer :: itr, jtr
   real(wp), parameter :: kp(3) = [1.1_wp, 1.2_wp, 1.2_wp]

   if (izp == 1 .and. jzp == 1) then
      kpair = 0.96_wp
   else if (izp ==  5 .and. jzp == 1 .or. izp == 1 .and. jzp == 5) then
      kpair = 0.95_wp
   else if (izp ==  7 .and. jzp == 1 .or. izp == 1 .and. jzp == 7) then
      kpair = 1.04_wp
   else if (izp == 28 .and. jzp == 1 .or. izp == 1 .and. jzp == 28) then
      kpair = 0.90_wp
   else if (izp == 75 .and. jzp == 1 .or. izp == 1 .and. jzp == 75) then
      kpair = 0.80_wp
   else if (izp == 78 .and. jzp == 1 .or. izp == 1 .and. jzp == 78) then
      kpair = 0.80_wp
   else if (izp == 15 .and. jzp == 5 .or. izp == 5 .and. jzp == 15) then
      kpair = 0.97_wp
   else if (izp == 14 .and. jzp == 7 .or. izp == 7 .and. jzp == 14) then
      kpair = 1.01_wp
   else
      itr = get_dblock_row(izp)
      jtr = get_dblock_row(jzp)
      if (itr > 0 .and. jtr > 0) then
         kpair = 0.5_wp * (kp(itr) + kp(jtr))
      else
         kpair = 1.0_wp
      end if
   end if
end function get_pair_param

elemental function get_dblock_row(zp) result(tr)
   integer, intent(in) :: zp
   integer :: tr

   if (zp > 20 .and. zp < 30) then
      tr = 1
   else if (zp > 38 .and. zp < 48) then
      tr = 2
   else if (zp > 56 .and. zp < 80) then
      tr = 3
   else
      tr = 0
   end if

end function get_dblock_row

!> Generator for the enhancement factor to for scaling Hamiltonian elements
subroutine get_hscale(self, mol, bas, hscale)
   !> Instance of the Hamiltonian specification
   class(gfn1_h0spec), intent(in) :: self
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Scaling parameters for the Hamiltonian elements
   real(wp), intent(out) :: hscale(:, :, :, :)

   real(wp), parameter :: enscale = -7.0e-3_wp
   real(wp), parameter :: kdiff = 2.85_wp
   integer :: isp, jsp, izp, jzp, ish, jsh, il, jl
   real(wp) :: den, enp, km

   hscale(:, :, :, :) = 0.0_wp

   do isp = 1, mol%nid
      izp = mol%num(isp)
      do jsp = 1, mol%nid
         jzp = mol%num(jsp)
         den = (get_pauling_en(izp) - get_pauling_en(jzp))**2
         do ish = 1, bas%nsh_id(isp)
            il = bas%cgto(ish, isp)%ang
            do jsh = 1, bas%nsh_id(jsp)
               jl = bas%cgto(jsh, jsp)%ang
               if (self%valence(ish, isp) .and. self%valence(jsh, jsp)) then
                  enp = 1.0_wp + enscale * den
                  km = self%kpair(jsp, isp) * self%kshell(jl, il) * enp
               else if (self%valence(ish, isp) .and. .not.self%valence(jsh, jsp)) then
                  km = 0.5_wp * (self%kshell(il, il) + kdiff)
               else if (.not.self%valence(ish, isp) .and. self%valence(jsh, jsp)) then
                  km = 0.5_wp * (self%kshell(jl, jl) + kdiff)
               else
                  km = kdiff
               end if
               hscale(jsh, ish, jsp, isp) = km
            end do
         end do
      end do
   end do
end subroutine get_hscale


!> Generator for the self energy / atomic levels of the Hamiltonian
subroutine get_selfenergy(self, mol, bas, selfenergy)
   !> Instance of the Hamiltonian specification
   class(gfn1_h0spec), intent(in) :: self
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Self energy / atomic levels
   real(wp), intent(out) :: selfenergy(:, :)

   integer :: isp, izp, ish

   selfenergy(:, :) = 0.0_wp

   do isp = 1, mol%nid
      izp = mol%num(isp)
      do ish = 1, bas%nsh_id(isp)
         selfenergy(ish, isp) = p_selfenergy(ish, izp)
      end do
   end do
end subroutine get_selfenergy


!> Generator of the coordination number dependent shift of the self energy
subroutine get_cnshift(self, mol, bas, kcn)
   !> Instance of the Hamiltonian specification
   class(gfn1_h0spec), intent(in) :: self
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Coordination number dependent shift
   real(wp), intent(out) :: kcn(:, :)

   integer :: isp, izp, ish, il, ik

   real(wp), parameter :: cnshell(2, 0:2) = reshape(&
      &[0.6_wp, 0.6_wp,-0.3_wp,-0.3_wp,-0.5_wp, 0.5_wp], &
      & shape(cnshell)) * 0.01_wp

   kcn(:, :) = 0.0_wp
   do isp = 1, mol%nid
      izp = mol%num(isp)
      ik = gfn1_kinds(izp)
      if (ik > 0) then
         do ish = 1, bas%nsh_id(isp)
            il = bas%cgto(ish, isp)%ang
            kcn(ish, isp) = - p_selfenergy(ish, izp) * cnshell(ik, il)
         end do
      end if
   end do
end subroutine get_cnshift


!> Generator for the polynomial parameters for the distant dependent scaling
subroutine get_shpoly(self, mol, bas, shpoly)
   !> Instance of the Hamiltonian specification
   class(gfn1_h0spec), intent(in) :: self
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Polynomial parameters for distant dependent scaleing
   real(wp), intent(out) :: shpoly(:, :)

   integer :: isp, izp, ish

   shpoly(:, :) = 0.0_wp

   do isp = 1, mol%nid
      izp = mol%num(isp)
      do ish = 1, bas%nsh_id(isp)
         shpoly(ish, isp) = p_shpoly(bas%cgto(ish, isp)%ang, izp)
      end do
   end do
end subroutine get_shpoly


subroutine get_reference_occ(self, mol, bas, refocc)
   !> Instance of the Hamiltonian specification
   class(gfn1_h0spec), intent(in) :: self
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Reference occupation numbers
   real(wp), intent(out) :: refocc(:, :)

   integer :: isp, izp, ish

   refocc(:, :) = 0.0_wp

   do isp = 1, mol%nid
      izp = mol%num(isp)
      do ish = 1, bas%nsh_id(isp)
         if (self%valence(ish, isp)) then
            refocc(ish, isp) = reference_occ(bas%cgto(ish, isp)%ang, izp)
         else
            refocc(ish, isp) = 0.0_wp
         end if
      end do
   end do
end subroutine get_reference_occ


subroutine get_hubbard_derivs(mol, bas, hubbard_derivs)
   !> Molecular structure data
   type(structure_type), intent(in) :: mol
   !> Basis set information
   type(basis_type), intent(in) :: bas
   !> Shell resolved Hubbard derivatives
   real(wp), allocatable, intent(out) :: hubbard_derivs(:, :)

   real(wp), parameter :: shell_hubbard_derivs(0:2) = [1.0_wp, 0.5_wp, 0.25_wp]

   integer :: isp, izp, ish, il

   allocate(hubbard_derivs(maxval(bas%nsh_id), mol%nid))
   hubbard_derivs(:, :) = 0.0_wp
   do isp = 1, mol%nid
      izp = mol%num(isp)
      do ish = 1, bas%nsh_id(isp)
         il = bas%cgto(ish, isp)%ang
         hubbard_derivs(ish, isp) = p_hubbard_derivs(izp) * shell_hubbard_derivs(il)
      end do
   end do
end subroutine get_hubbard_derivs

end module tblite_xtb_gfn1
