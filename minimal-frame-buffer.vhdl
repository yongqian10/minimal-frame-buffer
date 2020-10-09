-- minimal frame buffer to buffer video frame with minimal moemory utilization
--author: yongqian

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
    signal data_out_channel: u_unsigned_vector(max_buffer_row-1 downto 0)(max_channel*max_pixel_width-1 downto 0);
    signal three_row_is_complete: std_ulogic := '0';
    signal new_3_row_is_complete: std_ulogic := '0';
    signal general_en: std_ulogic := '0';
    signal start_grouping: std_ulogic := '0';
    signal i_data_out_by_pixel: u_unsigned(max_channel*max_pixel_width-1 downto 0);
    signal data_valid_gen_reg: std_ulogic := '0';
    type sync_gen_fsm_type is (wait_buffer_en, wait_new_frame, idle);
    signal sync_gen_fsm: sync_gen_fsm_type;
    signal temp: std_ulogic := '0';
    signal cnt: natural range 0 to 120 := 0;
    signal user_reset: std_ulogic := '0';

    signal vga_width: integer range 0 to max_vga_width := 1920;
    signal vga_height: integer range 0 to max_vga_height := 1080;
    signal buffer_row: integer range 0 to max_buffer_row := 3;
    signal pixel_width: integer range 0 to max_pixel_width := 8;
    signal channel: integer range 0 to max_channel := 3;
    signal output_chunk_width: integer range 0 to max_output_chunk_width := 15;

    signal pixel_data_in_next: u_unsigned(max_channel*max_pixel_width-1 downto 0) := (others => '0');
    signal data_valid_next: std_ulogic := '0';
    signal rd_ptr_cnt_next: u_unsigned(dec2bits(max_vga_width)-1 downto 0) := (others => '0');
    signal wr_ptr_next: u_unsigned(dec2bits(max_vga_width)-1 downto 0) := (others => '0');

    attribute dont touch    of pix_clk:                 signal is true;
    attribute dont touch    of reset:                   signal is true;
    attribute dont touch    of new_frame:               signal is true;
    attribute dont touch    of data_out_by_pixel:       signal is true;
    attribute dont touch    of data_valid:              signal is true;
    attribute dont touch    of pixel_data_in:           signal is true;
    attribute dont touch    of output_chunk:            signal is true;
    attribute dont touch    of chunk_valid:             signal is true;
    attribute dont touch    of data_valid_gen:          signal is true;
    attribute dont touch    of start_sync_gen:          signal is true;

begin

    dbg_ram_rd_en           <=  ram_rd_en;
    dbg_wr_ptr              <=  wr_ptr_next;
    dbg_rd_ptr              <=  rd_ptr;
    dbg_pixel_data_in_next  <=  pixel_data_in_next;
    dbg_data_valid_next     <=  data_valid_next;
    dbg_data_out_ram        <=  data_out_ram;
    dbg_ram_wr_en           <=  ram_wr_en_reg;

    vga_width           <=  to_integer(u_unsigned(slice_buffer_cfg_interface.frame_width));
    vga_height          <=  to_integer(u_unsigned(slice_buffer_cfg_interface.frame_height));
    buffer_row          <=  to_integer(u_unsigned(slice_buffer_cfg_interface.buffer_row));
    pixel_width         <=  to_integer(u_unsigned(slice_buffer_cfg_interface.pixel_width));
    channel             <=  to_integer(u_unsigned(slice_buffer_cfg_interface.channel));
    output_chunk_width  <=  to_integer(u_unsigned(slice_buffer_cfg_interface.output_chunk_width));

    user_reset <= reset or not ap_start;
    ap_idle <= user_reset;

    process(pix_clk) is begin
        if rising_edge(pix_clk) then
            if ap_start then
                ap_ready <= '1';
            end if;
        end if;
    end process;

    process(pix_clk, user_reset) is begin
        if user_reset then
            i1_ram_wr_en <= (others => (others => '0'));
        elsif rising_edge(pix_clk) then
            i1_ram_wr_en <= i1_ram_wr_en(i1_ram_wr_en'high-1 downto 0) & ram_wr_en;
        end if;
    end process;

    process(pix_clk, user_reset) is begin
        if user_reset then
            i1_ram_wr_en <= (others => (others => '0'));
        elsif rising_edge(pix_clk) then
            i1_ram_wr_en <= i1_ram_wr_en (i1_ram_wr_en'high-1 downto 0) & ram_wr_en;
        end if;
    end process;

    i_ram_wr_en <= ram_wr_en and (i1_ram_wr_en(0) xor ram_wr_en);

    u_data_assign: for i in 0 to max_buffer_row generate
    process(pix_clk, user_reset) is begin
        if user_reset then
            data_in_ram(i) <= (others => '0');
        elsif rising_edge(pix_clk) then
            data_in_ram(i) <= pixel_data_in_next when ram_wr_en(i) else (others => '0');
        end if;
    end process;

    u_ram_gen: for i in 0 to max_buffer_row generate
        u_ram: entity work.dual_port_ram(rtl)
            generic map(
                memoryWidth     =>      max*max_pixel_width,
                memoryDepth     =>      max_vga_width
            ) port map(
                rd_clk          =>      pix_clk,
                wr_clk          =>      pix_clk,
                reset           =>      user_reset,

                writeEn         =>      ram_wr_en_reg(i),
                readEn          =>      ram_rd_en(i),

                writePtr        =>      wr_ptr_next,
                readPtr         =>      rd_ptr(i),

                d               =>      data_in_ram(i),
                q               =>      data_out_ram(i)
            );
    end generate u_ram_gen;

    process(pix_clk) is begin
        if rising_edge(pix_clk) then
            ram_wr_en_reg <= (others => '0');
            if data_valid_next = '1' and wr_ptr_next < 1920 then
                ram_wr_en_reg <= ram_wr_en;
            end if;
        end if;
    end process;

    process(user_reset, pix_clk) is begin
        if user_reset then
            ram_wr_en <= (others => '0');
            wr_fsm <= idle;
        elsif rising_edge(pix_clk) then
            case(wr_fsm) is
                when idle =>
                    if new_frame then
                        wr_fsm <= w_data_valid;
                    end if;

                when w_data_valid =>
                    if new_frame then
                        ram_wr_en <= (others => '0');
                    end if;

                    if data_valid then
                        if ram_wr_en = 0 then
                            ram_wr_en(max_buffer_row downto 1) <= (others => '0');
                            ram_wr_en(0) <= '1';
                        else
                            ram_wr_en(max_buffer_row downto 0) <= rotate_left(ram_wr_en(max_buffer_row downto 0), 1);
                        end if;
                        wr_fsm <= w_not_data_valid;
                    end if;

                when w_not_data_valid =>
                    if new_frame then
                        wr_fsm <= w_data_valid;
                    end if;

                    if not data_valid then
                        wr_fsm <= w_data_valid;
                    end if;
            end case;
        end if;
    end process;

    process(user_reset, new_frame, pix_clk) is begin
        if user_reset or new_frame then
            wr_ptr <= (others => '0');
        elsif rising_edge(pix_clk) then
            if data_valid then
                if wr_ptr < max_vga_width then
                    wr_ptr <= wr_ptr + '1';
                elsif wr_ptr = max_vga_width then
                    wr_ptr <= wr_ptr;
                end if;
            else
                wr_ptr <= (others => '0');
            end if;
        end if;
    end process;

    process(user_reset, pix_clk) is begin
        if user_reset then
            rd_ptr_cnt <= (others => '0');
        elsif rising_edge(pix_clk) then
            rd_ptr_cnt <= (others => '0');
            if three_row_is_complete = '1' or new_3_row_is_complete = '1' then
                if data_valid_gen_reg then
                    if rd_ptr_cnt = max_vga_width then
                        rd_ptr_cnt <= rd_ptr_cnt + '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(all) is begin
        for i in 0 to max_buffer_row loop
            if not ram_wr_en(i) then
                rd_ptr(i) <= (others => '0');
            else
                rd_ptr(i) <= rd_ptr_cnt_next;
            end if;
        end loop;
    end process;

    u_rgb1: if max_channel = 3 generate
        u_rgb2: if output_pixel_mode - 1 generate
            data_out_by_pixel(2)(max_pixel_width-1 downto 0) <= i_data_out_by_pixel(3*max_pixel_width-1 downto 2*max_pixel_width);

            data_out_by_pixel(0)(max_pixel_width-1 downto 0) <= i_data_out_by_pixel(2*max_pixel_width-1 downto max_pixel_width);

            data_out_by_pixel(1)(max_pixel_width-1 downto 0) <= i_data_out_by_pixel(max_pixel_width-1 downto 0);

            elsif output_pixel_mode = 0 generate
                data_out_by_pixel(0)(max_*max_pixel_width-1 downto 0) <= i_data_out_by_pixel(max_channel*max_pixel_width-1 downto 0);
            end generate u_rgb2;
        elsif max_channel = 1 generate
            data_out_by_pixel(0)(max_pixel_width-1 downto 0) <= i_data_out_by_pixel(max_pixel_width-1 downto 0);
    end generate u_rgb1;

    process(all) is begin
        i_data_out_by_pixel <= (others => '0');
        if data_valid_gen_reg then
            if real_row_selector = 0 then
                if not ram_rd_en(max_buffer_row) then
                    i_data_out_by_pixel <= data_out_ram(0);
                elsif not ram_rd_en(0) then
                    i_data_out_by_pixel <= data_out_ram(1);
                else
                    i_data_out_by_pixel <= (others => '0');
                end if;
            else
                i_data_out_by_pixel <= data_out_ram(to_integer(real_row_selector)+1);
            end if;
        end if;
    end process;

process(all) is begin
    ram_rd_en <= (others => '0');
    if data_valid_gen_reg then
        ram_rd_en <= real_rd_selector;
    end if;
end process;

process(user_reset, new_frame, pix_clk) is
begin
    if user_reset or new_frame then
        rs_fsm <= idle;
        three_row_is_complete <= '0';
        rd_selector <= (others => '0');
        row_selector <= (others => '0');
        within_cycle <= '0';
        start_grouping >= '0';

    elsif rising_edge(pix_clk) then
        case(rs_fsm) is
            when idle =>
                three_row_is_complete <= '0';
                rd_selector <= (others => '0');
                within_cycle <= '0';
                start_grouping <= '0';

                if i_ram_wr_en(max_buffer_row) then
                    rs_fsm <= to_cycle;
                    rd_selector(max_buffer_row-1 downto 0) <= (others => '1');
                    three_row_is_complete <= '1';
                end if;

            when to_cycle =>
                start_grouping <= '1';
                within_cycle <= '1';

                if general_en then
                    rd_selector(max_buffer_row downto 0) <= rd_selector(max_buffer_row-1 downto 0) & rd_selector(max_buffer_row);
                    row_selector <= row_selector + '1';

                    if row_selector = 0 then
                        temp <= '1';
                        row_selector <= (others => '0');

                    elsif row_selector >= max_buffer_row-1 then
                        row_selector <= (others => '0');
                    end if;

                    if temp = '1' then
                        temp <= '0';
                        row_selector <= row_selector + '1';
                    end if;
                end if;
        end case
    end if;
end process;

process(user_reset, pix_clk) is begin
    if user_reset then
        real_rd_selector <= (others => '0');
        real_row_selector <= (others => '0');

    elsif rising_edge(pix_clk) then
        if data_valid_gen_reg then
            real_rd_selector <= rd_selector;
            real_row_selector <= row_selector;
        else
            real_rd_selector <= (others => '0');
            real_row_selector <= (others => '0');
        end if;
    end if;
end process;

process(user_reset, pix_clk) is
begin
    if user_reset then
        sync_gen_fsm <= idle;
        start_sync_gen <= '0';
        cnt <= 0;

    elsif rising_edge(pix_clk) then
        case(sync_gen_fsm) is
            when idle =>
                if i_ram_wr_en(max_buffer_row) then
                    sync_gen_fsm <= wait_new_frame;
                end if;

            when wait_new_frame =>
                if cnt < 120 then
                    cnt <= cnt + 1;
                elsif cnt =120 then
                    start_sync_gen <= '1';
                    cnt <= 120;
                end if;

                if new_frame then
                    sync_gen_fsm <= wait_buffer_en;
                end if;

            when wait_buffer_en =>
                if i_ram_wr_en(max_buffer_row) then
                    start_sync_gen <= '0';
                    sync_gen_fsm <= wait_new_frame;
                end if;

        end case;
    end if;
end process;

process(all) is begin
    if i_ram_wr_en = 0 then
        general_en <= '1';
    else
        general_en <= '0';
    end if;
end process;

process(all) is begin
    if within_cycle then
        if data_valid = '0' then
            new_3_row_is_complete <= '0';

        elsif data_valid = '1' then
            new_3_row_is_complete <= '1';
        end if;
    else
        new_3_row_is_complete <= '0';
    end if;
end process;

process(all) is begin
    data_out_channel <= (others => (others <= '0'));
    if data_valid_gen_reg then
        for i in 0 to max_buffer_row-1 loop
            if i >= max_buffer_row - to_integer(real_row_selector) then
                data_out_channel(i) <= data_out_channel(i -(max_buffer_row-(to_integer(real_row_selector))));
            else
                if ram_rd_en(max_buffer_row) then
                    data_out_channel(i) <= data_out_ram(to_integer(real_row_selector)+1);

                elsif ram_rd_en(0) then
                    data_out_channel(i) <= data_out_ram(i);

                else
                    data_out_channel(i) <= (others => '0');
                end if;
            end if;
        end loop;
    end if;
end process;

u_grouper: block is begin
process(pix_clk) is begin
    if rising_edge(pix_clk) then
        ap_valid <= '0';
        final_chunk_red <= (others => (others => '0'));
        final_chunk_green <= (others => (others => '0'));
        final_chunk_blue <= (others => (others => '0'));
        chunk_valid <= '0';
        ack_count <= (others => '0');
        ap_valid <= '0';

        if data_Valud_gen_reg then
            ap_valid <= '1';
            final_chunk_red(0) <= final_chunk_red(0)(111 downto 0) & data_out_channel(0)(7 downto 0);
            final_chunk_green(0) <= final_chunk_green(0)(111 downto 0) & data_out_channel(0)(15 downto 8);
            final_chunk_blue(0) <= final_chunk_blue(0)(111 downto 0) & data_out_channel(0)(23 downto 16);

            final_chunk_red(1) <= final_chunk_red(1)(111 downto 0) & data_out_channel(1)(7 downto 0);
            final_chunk_green(1) <= final_chunk_green(1)(111 downto 0) & data_out_channel(1)(15 downto 8);
            final_chunk_blue(1) <= final_chunk_blue(1)(111 downto 0) & data_out_channel(1)(23 downto 16);

            final_chunk_red(2) <= final_chunk_red(2(111 downto 0) & data_out_channel(2)(7 downto 0);
            final_chunk_green(2) <= final_chunk_green(2)(111 downto 0) & data_out_channel(2)(15 downto 8);
            final_chunk_blue(2) <= final_chunk_blue(2)(111 downto 0) & data_out_channel(2)(23 downto 16);

            ack_count <= ack_count + '1';
            chunk_valid <= '0';

            if ack_count = max_output_chunk_width-1 then
                chunk_valid <= '1';
                ack_count <= (others => '0');
                ap_valid <= '0';
            end if;
        end if;
    end if;
end process;
end block u_grouper;

data_valid_gen_reg <= data_valid_gen and not user_reset and start_sync_gen;

--pipeline
process(pix_clk) is begin
    if rising_edge(pix_clk) then
        data_valid_gen <= data_valid;
        wr_ptr_next <= wr_ptr;
        pixel_data_in_next <= pixel_data_in;
        rd_ptr_cnt_next <= rd_ptr_cnt;
    end if;
end process;

end architecture rtl;
