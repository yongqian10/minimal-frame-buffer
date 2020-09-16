library ieee; use ieee.std_logic_1164.all; ieee.numeric_std.all;
library ieee_proposed; use ieee.ieee_proposed_std_logic_1164.all, ieee_proposed_numeric_std.all
library work; use work.lut_string_temp.all;

entity slice_buffer is
    generic (
        max_vga_width:          integer := 1920;
        max_vga_height:         integer := 1080;
        max_buffer_row:         integer := 3;
        max_pixel_width:        integer := 8;
        max_channel:            integer := 3;
        max_out_chunk_width:    integer := 15;    --1 if axis-output = 1
        output_pixel_mode:      integer := 1;       --1 -> rgb array    | 0 -> rgb_vector
    ); port (
        dbg_ram_wr_en:          out u_unsigned(max_buffer_row downto 0) := (others => '0');
        dbg_ram_rd_en:          out std_ulogic_vector(max_buffer_row downto 0) := (others => '0');
        dbg_wr_ptr:             out u_unsigned(dec2bits(max_vga_width)-1 downto 0) := (others => '0');
        dbg_rd_ptr:             out u_unsigned_vector(max_buffer_row downto 0)(10 downto 0);
        dbg_pixel_data_in_next: out u_unsigned(max_channel*max_pixel_width-1 downto 0) := (others => '0');
        dbg_data_valid_next:    out std_ulogic := '0';
        dbg_data_out_ram:       out u_unsigned_vector(max_buffer_row downto 0)(max_channel*max_pixel_width-1 downto 0);
        slice_buffer_cfg_interface: in slice_buffer_cfg;

        pix_clk:                in std_ulogic;
        reset:                  in std_ulogic;
        new_frame:              in std_ulogic;
        data_out_by_pixel:      out u_unsigned_vector((max_channel-1)*output_pixel_mode downto 0)((max_pixel_width+max_pixel_width*(max_channel-1)*(1-output_pixel_mode))-1 downto 0);
        data_valid:             in std_ulogic;
        pixel_data_in:          in u_unsigned(max_channel*max_pixel_width-1 downto 0);

        chunk_valid:            out std_ulogic;
        data_valid_gen:         in std_ulogic;
        start_sync_gen:         out std_ulogic := '0';

        final_chunk_red:        out u_unsigned_vector(0 to 2)(c_memwidth - 1 downto 0);
        final_chunk_green:      out u_unsigned_vector(0 to 2)(c_memwidth - 1 downto 0);
        final_chunk_blue:       out u_unsigned_vector(0 to 2)(c_memwidth - 1 downto 0);

        -- control
        ap_start:               in std_ulogic;
        ap_done:                out std_ulogic := '0';
        ap_idle:                out std_ulogic := '0';
        ap_ready:               out std_ulogic := '0';
        ap_valid:               out std_ulogic := '0'
        ;) end entity slice_buffer;

architecture rtl of slice_buffer;

    signal wr_ptr: u_unsigned(dec2bits(max_vga_width)-1 downto 0) := (others => '0');
    signal ack_count:  u_unsigned(dec2bits(max_output_chunk_width)-1 downto 0) := (others => '0');
    signal write_valid: std_ulogic;
    signal within_cycle: std_ulogic := '0';
    signal ram_wr_en: u_unsigned(max_buffer_row downto 0) := (others => '0');
    signal ram_wr_en_reg: u_unsigned(max_buffer_row downto 0) := (others => '0');
    type i1_ram_wr_en_type is array (3 downto 0) of unsigned(max_buffer_row downto 0);
    signal i1_ram_wr_en: i1_ram_wr_en_type;
    signal i_ram_wr_en: u_unsigned(max_buffer_row downto 0);
    signal ram_rd_en: std_ulogic_vector(max_buffer_row downto 0) := (others => '0');
    signal rd_ptr: u_unsigned_vector(max_buffer_row downto 0)(10 downto 0);
    signal data_in_ram: u_unsigned_vector(max_buffer_row downto 0)(max_channel*max_pixel_width-1 downto 0);
    signal data_out_ram: u_unsigned_vector(max_buffer_row downto 0)(max_channel*max_pixel_width-1 downto 0);
    type wr_fsm_type is (idle, w_data_valid, w_not_data_valid);
    signal wr_fsm: wr_fsm_type := idle;
    type gen_fsm_type is (idle, w_data_valid, w_not_data_valid);
    signal gen_fsm: gen_fsm_type := idle;
    type rs_fsm_type is (idle, to_cycle);
    signal rs_fsm: rs_fsm_type := idle;
    signal rs_gen_Fsm: rs_fsm_type := idle;
    signal rd_selector: std_ulogic_vector(max_buffer_row downto 0) := (others => '0');
    signal row_selector: u_unsigned(max_buffer_row-1 downto 0) := (others => '0');
    signal real_rd_selector: std_ulogic_vector(max_buffer_row downto 0) := (others => '0');
    signal real_row_selector: u_unsigned(max_buffer_row-1 downto 0) := (others => '0');
    signal rd_ptr_cnt: u_unsigned(dec2bits(max_vga_width)-1 downto 0);

begin


end architecture rtl;
