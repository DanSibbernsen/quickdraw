/*
 * "Copyright (c) 2006 Washington University in St. Louis.
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL WASHINGTON UNIVERSITY IN ST. LOUIS BE LIABLE TO ANY PARTY
 * FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING
 * OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF WASHINGTON
 * UNIVERSITY IN ST. LOUIS HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * WASHINGTON UNIVERSITY IN ST. LOUIS SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND WASHINGTON UNIVERSITY IN ST. LOUIS HAS NO
 * OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR
 * MODIFICATIONS."
 */

/**
 * @author Kevin Klues (klueska@cs.wustl.edu)
 * @version $Revision: 1.2 $
 * @date $Date: 2008/08/06 16:20:46 $
 */

import java.io.File;
import java.io.IOException;

import net.tinyos.message.*;
import net.tinyos.tools.*;
import net.tinyos.packet.*;
import net.tinyos.util.*;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import java.util.ArrayList;
import java.util.Properties;

public class PrintfClient implements MessageListener {

  private MoteIF moteIF;
  public static String driver = "org.apache.derby.jdbc.EmbeddedDriver";
  public static String protocol = "jdbc:derby:";
  public static String sqlCreateTbl = "create table quickdraw(moteID int, time int, win int, draw int)";
  public static String bufferSave = null;

  public static String sqlGetStats = "SELECT SUM(win) as win, " +
					"SUM(case when win = 0 then 1 else 0 end) as lose, " +
					"SUM(draw) as draw, " +
					"MIN(time) as time " +
					"FROM quickdraw WHERE moteID = ";
  
  public static PreparedStatement sqlInsert = null;
  public static Connection conn = null;
  public static QuickD qd;
  
  public PrintfClient(MoteIF moteIF) {
    this.moteIF = moteIF;
    this.moteIF.registerListener(new PrintfMsg(), this);
  }

  public void messageReceived(int to, Message message) {
    PrintfMsg msg = (PrintfMsg)message;
    String input = null;
    String[] inputSplit = null;
    String[] output = {""};
    boolean newChar = false;
    
    if(bufferSave != null) {
    	input = bufferSave;
    	bufferSave = null;
    }
    
    for(int i=0; i<msg.totalSize_buffer(); i++) {
      char nextChar = (char)(msg.getElement_buffer(i));
      if(nextChar != 0) {
    	  if(input == null)
    		  input = Character.toString(nextChar);
    	  else
    		  input += nextChar;
      } 
    }
    
    if(input.toCharArray()[input.length() - 1] == '\n')
    	newChar = true;
    	
    inputSplit = input.split("\n");
    for (int i = 0; i < inputSplit.length; i++) {
	    if(inputSplit[i].contains("$")) {
	    	parseInput(inputSplit[i]);
	    	input = input.replace(inputSplit[i], "");
	    }
    }
    
    if (!input.matches("\\n*"))
    	qd.updateText(input);
  }
  
  private static void usage() {
    System.err.println("usage: PrintfClient [-comm <source>]");
  }
  
  public static void main(String[] args) throws Exception {
    String source = null;
    if (args.length == 2) {
      if (!args[0].equals("-comm")) {
	       usage();
	       System.exit(1);
      }
      source = args[1];
    }
    
    PhoenixSource phoenix;
    if (source == null) {
      phoenix = BuildSource.makePhoenix(PrintStreamMessenger.err);
    }
    else {
      phoenix = BuildSource.makePhoenix(source, PrintStreamMessenger.err);
    }
    System.out.print(phoenix);
    MoteIF mif = new MoteIF(phoenix);
    PrintfClient client = new PrintfClient(mif);
    
    initDB();

    qd = new QuickD();
    qd.setVisible(true);
    //clearTable();
    loadStats();
  }
  
  static void initDB() {   
    ArrayList statements = new ArrayList();
    Statement s = null;
    ResultSet rs = null;
    Properties props = new Properties();
    
    try {
        Class.forName(driver).newInstance();
        props.put("user", "quick");
        props.put("password", "quickdraw");
        String dbName = "quickDB";
        try {
        conn = DriverManager.getConnection(protocol + dbName, props);
        } catch (SQLException ex) {
        	conn = DriverManager.getConnection(protocol + dbName + ";create=true", props);
	        conn.setAutoCommit(true);
	        s = conn.createStatement();
	        statements.add(s);
	        s.execute(sqlCreateTbl);
        }
        
        sqlInsert = conn.prepareStatement("insert into quickdraw values(?, ?, ?, ?)");
        statements.add(sqlInsert);
    }
    catch (Exception ex){ ex.printStackTrace();}
  }
  
  static void parseInput(String input) {
	  String[] split = input.split(" ");
	  
	  if (!input.matches("\\$\\s[0-9]\\s[0-9]+\\s[0-9]\\s[0-9]")) {
		  bufferSave = new String(input);
		  return;
	  }
		  

	  int id = Integer.parseInt(split[1]);
	  int time = Integer.parseInt(split[2]);
	  int win = Integer.parseInt(split[3]);
	  int draw = Integer.parseInt(split[4]);
	  
	  try{
		  sqlInsert.setInt(1, id);
		  sqlInsert.setInt(2, time);
		  sqlInsert.setInt(3, win);
		  sqlInsert.setInt(4, draw);
		  sqlInsert.executeUpdate();
		  conn.commit();
	  }
	  catch (Exception ex){}
	  
	  qd.updateStats(id, time, win, draw);
  }
  
  static void loadStats(){
	  String sqlStats;
	  ResultSet rs;
	  Statement stat;
	  String win = null, time = null, lose = null, draw = null;
	  
	  for(int i = 0; i < 2; i ++){
		  try {			  
			sqlStats = sqlGetStats + i;
			stat = conn.createStatement();
			rs = stat.executeQuery(sqlStats);
			
			while(rs.next()){				
				if ((win = rs.getString("win")) == null)
					win = "0";
				if ((lose = rs.getString("lose")) == null)
					lose = "0";
				if ((draw = rs.getString("draw")) == null)
					draw = "0";
				if ((time = rs.getString("time")) == null)
					time = "0";
			}
		  } catch (SQLException e) {
			  e.printStackTrace();
		  }

		  qd.setStats(i, win, time, lose, draw);
	  }
  }
  
  static void clearTable(){
	  Statement stat;
	  try{
		  stat = conn.createStatement();
		  stat.execute("DELETE FROM quickdraw");
	  }
	  catch (Exception ex){}
  }
}
